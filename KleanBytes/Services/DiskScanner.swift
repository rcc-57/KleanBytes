import Foundation

enum DiskScanMode: Sendable, Equatable {
    case quick
    case full
}

struct ScanProgress: Sendable {
    let path: String
    let completedItems: Int
    let totalItems: Int

    var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return min(0.99, Double(completedItems) / Double(totalItems))
    }
}

struct ScanReport: Sendable {
    let root: FileSystemNode
    let issues: [String]
    let processedItemCount: Int
}

struct DiskScanner: Sendable {
    private let fileManager = FileManager.default
    private let resourceKeys: Set<URLResourceKey> = [
        .nameKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
        .fileResourceIdentifierKey, .isMountTriggerKey
    ]

    func scan(
        rootURL: URL,
        mode: DiskScanMode = .full,
        quickScanConfiguration: QuickScanConfiguration = .empty,
        estimatedItemCount: Int,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ScanReport {
        var state = ScanState(totalItems: max(1, estimatedItemCount))
        let root = try await scanItem(
            at: rootURL,
            mode: mode,
            quickScanConfiguration: quickScanConfiguration,
            state: &state,
            progress: progress
        )
        await progress(ScanProgress(
            path: rootURL.path,
            completedItems: state.processedItems,
            totalItems: state.totalItems
        ))
        return ScanReport(
            root: root,
            issues: state.issues,
            processedItemCount: state.processedItems
        )
    }

    private func scanItem(
        at url: URL,
        mode: DiskScanMode,
        quickScanConfiguration: QuickScanConfiguration,
        state: inout ScanState,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> FileSystemNode {
        try Task.checkCancellation()
        state.processedItems += 1
        if state.processedItems == 1 || state.processedItems.isMultiple(of: 128) {
            await progress(state.progress(path: url.path))
        }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: resourceKeys)
        } catch {
            state.issues.append("\(url.path): \(error.localizedDescription)")
            return inaccessibleNode(url)
        }

        let name = values.name ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
        let isSymbolicLink = values.isSymbolicLink == true
        let isDirectory = values.isDirectory == true && !isSymbolicLink

        if !isDirectory {
            state.fileCount += 1
            let identifier = values.fileResourceIdentifier.map { String(describing: $0) }
            let wasCounted = identifier.map { !state.seenFileIdentifiers.insert($0).inserted } ?? false
            let size = wasCounted ? 0 : Int64(
                values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            )
            let byteResult = state.scannedBytes.addingReportingOverflow(size)
            state.scannedBytes = byteResult.overflow ? Int64.max : byteResult.partialValue
            return FileSystemNode(
                id: url, name: name, url: url, isDirectory: false,
                isSymbolicLink: isSymbolicLink, size: size, children: [],
                fileCount: 1, directoryCount: 0, isAccessible: true, scanStatus: .complete
            )
        }

        state.directoryCount += 1
        if FileAccessPolicy.isApplicationsDirectory(url) {
            let displayedSize = ApplicationDirectorySizeCache.size(for: url)
                ?? indexedApplicationsSize(at: url)
                ?? -1
            return FileSystemNode(
                id: url, name: name, url: url, isDirectory: true,
                isSymbolicLink: false, size: displayedSize, children: [],
                fileCount: 0, directoryCount: 1, isAccessible: true, scanStatus: .complete
            )
        }
        let childURLs: [URL]
        do {
            childURLs = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            )
        } catch {
            state.issues.append("\(url.path): \(error.localizedDescription)")
            return FileSystemNode(
                id: url, name: name, url: url, isDirectory: true,
                isSymbolicLink: false, size: 0, children: [],
                fileCount: 0, directoryCount: 1, isAccessible: false, scanStatus: .inaccessible
            )
        }

        var children: [FileSystemNode] = []
        children.reserveCapacity(childURLs.count)
        var totalSize: Int64 = 0
        var fileCount = 0
        var directoryCount = 1
        var status: NodeScanStatus = .complete

        for childURL in childURLs {
            try Task.checkCancellation()
            if childURL.lastPathComponent == ".localized" { continue }

            if shouldSkip(
                childURL,
                mode: mode,
                quickScanConfiguration: quickScanConfiguration
            ) {
                continue
            }
            let child = try await scanItem(
                at: childURL,
                mode: mode,
                quickScanConfiguration: quickScanConfiguration,
                state: &state,
                progress: progress
            )
            if mode == .quick,
               !quickScanConfiguration.includes(child),
               !(child.isDirectory && quickScanConfiguration.hasIncludedDescendant(of: child.url)) {
                continue
            }
            children.append(child)
            let countedSize = max(0, child.size)
            totalSize = totalSize.addingReportingOverflow(countedSize).overflow
                ? Int64.max
                : totalSize + countedSize
            fileCount += child.fileCount
            directoryCount += child.directoryCount
            if child.scanStatus != .complete { status = .partiallyAccessible }
        }

        return FileSystemNode(
            id: url, name: name, url: url, isDirectory: true,
            isSymbolicLink: false, size: totalSize, children: children,
            fileCount: fileCount, directoryCount: directoryCount,
            isAccessible: true, scanStatus: status
        )
    }

    private func inaccessibleNode(_ url: URL) -> FileSystemNode {
        FileSystemNode(
            id: url, name: url.lastPathComponent, url: url, isDirectory: false,
            isSymbolicLink: false, size: 0, children: [], fileCount: 0,
            directoryCount: 0, isAccessible: false, scanStatus: .inaccessible
        )
    }

    private func indexedApplicationsSize(at directory: URL) -> Int64? {
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: Int64 = 0
        var indexedItemCount = 0
        for child in children {
            if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                continue
            }
            guard let size = indexedSize(of: child), size >= 1_048_576 else {
                return nil
            }
            indexedItemCount += 1
            let result = total.addingReportingOverflow(size)
            total = result.overflow ? Int64.max : result.partialValue
        }
        return indexedItemCount > 0 ? total : nil
    }

    private func indexedSize(of url: URL) -> Int64? {
        guard let item = NSMetadataItem(url: url),
              let number = item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber else {
            return nil
        }
        return number.int64Value
    }

    private func shouldSkip(
        _ url: URL,
        mode: DiskScanMode,
        quickScanConfiguration: QuickScanConfiguration
    ) -> Bool {
        if DiskScanExclusions.contains(url) { return true }

        if mode == .quick, !quickScanConfiguration.shouldTraverse(url) {
            return true
        }

        let values = try? url.resourceValues(forKeys: [.isMountTriggerKey])
        return values?.isMountTrigger == true
    }

    private struct ScanState {
        let totalItems: Int
        var processedItems = 0
        var fileCount = 0
        var directoryCount = 0
        var scannedBytes: Int64 = 0
        var issues: [String] = []
        var seenFileIdentifiers: Set<String> = []

        func progress(path: String) -> ScanProgress {
            ScanProgress(
                path: path,
                completedItems: processedItems,
                totalItems: totalItems
            )
        }
    }
}

struct ApplicationDirectorySizeCalculator: Sendable {
    private let keys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
        .fileResourceIdentifierKey
    ]

    nonisolated init() {}

    nonisolated func size(
        at directory: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        var processedFiles = 0
        var seenIdentifiers: Set<String> = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            if let identifier = values.fileResourceIdentifier.map({ String(describing: $0) }),
               !seenIdentifiers.insert(identifier).inserted {
                continue
            }
            let size = Int64(
                values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            )
            let result = total.addingReportingOverflow(size)
            total = result.overflow ? Int64.max : result.partialValue
            processedFiles += 1
            if processedFiles.isMultiple(of: 4_096) {
                progress(total)
            }
        }
        progress(total)
        return total
    }
}

enum ApplicationDirectorySizeCache {
    nonisolated private static let defaultsKey = "applicationDirectorySizesV2"

    nonisolated static func size(for url: URL) -> Int64? {
        let values = UserDefaults.standard.dictionary(forKey: defaultsKey)
        return (values?[url.standardizedFileURL.path] as? NSNumber)?.int64Value
    }

    nonisolated static func save(_ size: Int64, for url: URL) {
        var values = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
        values[url.standardizedFileURL.path] = NSNumber(value: size)
        UserDefaults.standard.set(values, forKey: defaultsKey)
    }
}
