import AppKit
import Foundation
import LocalAuthentication
import Observation
import SwiftUI

@MainActor
@Observable
final class DiskScannerViewModel {
    enum DeletionOutcome {
        case completed(String)
        case partiallyCompleted(String)
        case nothingDeleted(String)
    }

    enum AppState {
        case start
        case scanning
        case results
    }

    var appState: AppState = .start
    var volume: DiskVolume?
    var hasFullDiskAccess = false
    var currentPath = ""
    var scanningProgress = 0.0
    var isPreparingScan = false
    var scanIssues: [String] = []
    var navigationStack: [FileSystemNode] = []
    var selectedID: URL?
    var checkedIDs: Set<URL> = []
    var selectedNodes: [FileSystemNode] = []
    var unlockedIDs: Set<URL> = []
    var isDeletingSelection = false
    var quickScanConfiguration: QuickScanConfiguration
    var activeScanMode: DiskScanMode?
    var message: String?
    var errorMessage: String?

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var applicationSizeTask: Task<Void, Never>?
    init() {
        quickScanConfiguration = Self.loadQuickScanConfiguration()
        refreshDiskInformation()
        Self.removeLegacyScanCache()
    }

    var currentDirectory: FileSystemNode? { navigationStack.last }
    var canNavigateBack: Bool { navigationStack.count > 1 }

    func refreshDiskInformation() {
        hasFullDiskAccess = FullDiskAccessService.isGranted()
        do {
            volume = try DiskSpaceService.volume()
        } catch {
            errorMessage = "Не удалось прочитать информацию о диске: \(error.localizedDescription)"
        }
    }

    func startQuickScan() {
        beginScan(mode: .quick)
    }

    func startFullScan() {
        beginScan(mode: .full)
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        applicationSizeTask?.cancel()
        applicationSizeTask = nil
        resetToStart()
    }

    func returnToStart() {
        resetToStart()
    }

    func open(_ node: FileSystemNode) {
        guard node.isDirectory,
              node.isAccessible,
              !FileAccessPolicy.isApplicationsDirectory(node.url) else { return }
        navigationStack.append(node)
        selectedID = nil
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        navigationStack.removeLast()
        selectedID = nil
    }

    func revealInFinder(_ node: FileSystemNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func toggleChecked(_ node: FileSystemNode) {
        guard !FileAccessPolicy.isApplicationsDirectory(node.url),
              node.accessPolicy.isSelectable || unlockedIDs.contains(node.id) else { return }
        if !checkedIDs.insert(node.id).inserted {
            checkedIDs.remove(node.id)
            selectedNodes.removeAll { $0.id == node.id }
        } else {
            selectedNodes.append(node)
            selectedNodes.sort { lhs, rhs in
                if lhs.size == rhs.size { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
                return lhs.size > rhs.size
            }
        }
    }

    func removeFromSelection(_ node: FileSystemNode) {
        checkedIDs.remove(node.id)
        selectedNodes.removeAll { $0.id == node.id }
        if node.accessPolicy.showsLock {
            unlockedIDs.remove(node.id)
        }
        if selectedID == node.id {
            selectedID = nil
        }
    }

    func makeDeletionPlan() async -> SecureDeletionPlan {
        await FileDeletionService().makePlan(for: selectedNodes)
    }

    func permanentlyDeleteSelection(plan: SecureDeletionPlan) async -> DeletionOutcome {
        let nodes = selectedNodes
        guard !nodes.isEmpty else {
            return .nothingDeleted("Не выбрано ни одного объекта.")
        }

        isDeletingSelection = true
        defer { isDeletingSelection = false }
        do {
            let result = try await FileDeletionService().permanentlyDelete(plan)
            let removedPaths = Set(result.removedURLs.map { $0.standardizedFileURL.path })
            let deletedIDs = Set(
                nodes.filter { removedPaths.contains($0.url.standardizedFileURL.path) }.map(\.id)
            )
            checkedIDs.subtract(deletedIDs)
            selectedNodes.removeAll { deletedIDs.contains($0.id) }
            if let selectedID, deletedIDs.contains(selectedID) {
                self.selectedID = nil
            }
            if result.failures.isEmpty {
                let details = result.removedURLs.map(\.lastPathComponent).joined(separator: "\n")
                return .completed("Все выбранные объекты удалены:\n\n\(details)")
            } else {
                let removedDetails = result.removedURLs
                    .map(\.path)
                    .joined(separator: "\n")
                let failureDetails = result.failures
                    .map { "\($0.url.path)\nПричина: \($0.reason)" }
                    .joined(separator: "\n\n")
                refreshDiskInformation()
                if deletedIDs.isEmpty {
                    return .nothingDeleted("Ни один объект не был удалён.\n\nНе удалены:\n\(failureDetails)")
                }
                return .partiallyCompleted(
                    "Удаление выполнено частично.\n\nУдалены:\n\(removedDetails)\n\nНе удалены:\n\(failureDetails)\n\nВыполните сканирование заново, чтобы обновить результаты анализа."
                )
            }
        } catch {
            return .nothingDeleted("Ни один объект не был удалён.\n\nПричина: \(error.localizedDescription)")
        }
    }

    func finishDeletionFlow(message: String) {
        self.message = message
        resetToStart(preservingMessage: true)
    }

    func toggleQuickScanMembership(_ node: FileSystemNode) {
        quickScanConfiguration.toggle(node)
        Self.saveQuickScanConfiguration(quickScanConfiguration)
    }

    func updateQuickScanConfiguration(_ configuration: QuickScanConfiguration) {
        let sanitized = Self.sanitizedQuickScanConfiguration(configuration)
        quickScanConfiguration = sanitized
        Self.saveQuickScanConfiguration(sanitized)
    }

    func resetQuickScanConfiguration() {
        updateQuickScanConfiguration(.empty)
    }

    func lock(_ node: FileSystemNode) {
        unlockedIDs.remove(node.id)
        checkedIDs.remove(node.id)
        selectedNodes.removeAll { $0.id == node.id }
    }

    func unlock(_ node: FileSystemNode) async {
        guard node.accessPolicy.showsLock else { return }
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Разблокировать выбранный объект до окончания текущего сканирования"
            )
            unlockedIDs.insert(node.id)
        } catch let error as LAError where error.code == .userCancel || error.code == .systemCancel {
            return
        } catch {
            errorMessage = "Не удалось подтвердить личность: \(error.localizedDescription)"
        }
    }

    private func beginScan(mode: DiskScanMode) {
        guard scanTask == nil else { return }

        appState = .scanning
        activeScanMode = mode
        currentPath = "/"
        scanningProgress = 0
        isPreparingScan = false
        scanIssues = []
        navigationStack = []
        selectedID = nil
        checkedIDs = []
        selectedNodes = []
        unlockedIDs = []
        message = nil
        errorMessage = nil

        scanTask = Task {
            do {
                let countStore = ScanItemCountStore()
                let estimatedItemCount = countStore.itemCount(for: mode)
                    ?? defaultEstimatedItemCount(for: mode)
                let configuration = quickScanConfiguration
                let report = try await Task.detached(priority: .userInitiated) {
                    try await DiskScanner().scan(
                        rootURL: URL(fileURLWithPath: "/"),
                        mode: mode,
                        quickScanConfiguration: configuration,
                        estimatedItemCount: estimatedItemCount
                    ) { progress in
                        await MainActor.run {
                            self.currentPath = progress.path
                            self.scanningProgress = progress.fractionCompleted
                        }
                    }
                }.value

                try Task.checkCancellation()
                try? countStore.save(report.processedItemCount, for: mode)
                try Task.checkCancellation()
                navigationStack = [report.root]
                scanIssues = report.issues
                currentPath = report.root.url.path
                scanningProgress = 1
                isPreparingScan = false
                appState = .results
                refreshApplicationDirectorySizes(in: report.root)
            } catch is CancellationError {
                resetToStart()
            } catch {
                errorMessage = "Ошибка сканирования: \(error.localizedDescription)"
                resetToStart(preservingError: true)
            }
            scanTask = nil
        }
    }

    private func defaultEstimatedItemCount(for mode: DiskScanMode) -> Int {
        switch mode {
        case .full:
            2_000_000
        case .quick:
            1_000_000
        }
    }

    private func resetToStart(preservingError: Bool = false, preservingMessage: Bool = false) {
        applicationSizeTask?.cancel()
        applicationSizeTask = nil
        navigationStack = []
        scanIssues = []
        selectedID = nil
        checkedIDs = []
        selectedNodes = []
        unlockedIDs = []
        currentPath = ""
        scanningProgress = 0
        isPreparingScan = false
        activeScanMode = nil
        appState = .start
        refreshDiskInformation()
        if !preservingError {
            errorMessage = nil
        }
        if !preservingMessage {
            message = nil
        }
    }

    private func refreshApplicationDirectorySizes(in root: FileSystemNode) {
        applicationSizeTask?.cancel()
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Applications", isDirectory: true)
        ].filter { containsNode(with: $0.standardizedFileURL, in: root) }

        applicationSizeTask = Task {
            for url in candidates {
                guard !Task.isCancelled else { return }
                do {
                    let size = try await Task.detached(priority: .utility) {
                        try ApplicationDirectorySizeCalculator().size(at: url) { partialSize in
                            Task { @MainActor in
                                guard !Task.isCancelled else { return }
                                let currentSize = self.node(with: url, in: self.navigationStack.first)?.size ?? -1
                                if currentSize < 0 || partialSize > currentSize {
                                    self.replaceSize(of: url.standardizedFileURL, with: partialSize)
                                }
                            }
                        }
                    }.value
                    guard !Task.isCancelled else { return }
                    ApplicationDirectorySizeCache.save(size, for: url)
                    replaceSize(of: url.standardizedFileURL, with: size)
                } catch is CancellationError {
                    return
                } catch {
                    continue
                }
            }
            applicationSizeTask = nil
        }
    }

    private func containsNode(with id: URL, in node: FileSystemNode) -> Bool {
        if node.id.standardizedFileURL == id { return true }
        guard isAncestor(node.id, of: id) else { return false }
        return node.children.contains { containsNode(with: id, in: $0) }
    }

    private func node(with id: URL, in node: FileSystemNode?) -> FileSystemNode? {
        guard let node else { return nil }
        if node.id.standardizedFileURL == id.standardizedFileURL { return node }
        guard isAncestor(node.id, of: id) else { return nil }
        for child in node.children {
            if let match = self.node(with: id, in: child) { return match }
        }
        return nil
    }

    private func replaceSize(of id: URL, with size: Int64) {
        navigationStack = navigationStack.map { replacingSize(of: id, with: size, in: $0) }
    }

    private func replacingSize(
        of id: URL,
        with size: Int64,
        in node: FileSystemNode
    ) -> FileSystemNode {
        if node.id.standardizedFileURL == id {
            return copying(node, size: size, children: node.children)
        }
        guard isAncestor(node.id, of: id) else { return node }

        var changed = false
        let children = node.children.map { child in
            let updated = replacingSize(of: id, with: size, in: child)
            if updated.size != child.size { changed = true }
            return updated
        }
        guard changed else { return node }

        let oldChildrenSize = node.children.reduce(Int64(0)) { $0 + max(0, $1.size) }
        let newChildrenSize = children.reduce(Int64(0)) { $0 + max(0, $1.size) }
        let adjustedSize = max(0, node.size - oldChildrenSize + newChildrenSize)
        return copying(node, size: adjustedSize, children: children)
    }

    private func isAncestor(_ candidate: URL, of descendant: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let descendantPath = descendant.standardizedFileURL.path
        if candidatePath == "/" { return descendantPath.hasPrefix("/") }
        return descendantPath.hasPrefix(candidatePath + "/")
    }

    private func copying(
        _ node: FileSystemNode,
        size: Int64,
        children: [FileSystemNode]
    ) -> FileSystemNode {
        FileSystemNode(
            id: node.id,
            name: node.name,
            url: node.url,
            isDirectory: node.isDirectory,
            isSymbolicLink: node.isSymbolicLink,
            size: size,
            children: children,
            fileCount: node.fileCount,
            directoryCount: node.directoryCount,
            isAccessible: node.isAccessible,
            scanStatus: node.scanStatus
        )
    }

    nonisolated private static func loadQuickScanConfiguration() -> QuickScanConfiguration {
        let defaults = UserDefaults.standard
        let configuration = QuickScanConfiguration(
            includedPaths: Set(defaults.stringArray(forKey: "includedQuickScanPaths") ?? []),
            excludedPaths: Set(defaults.stringArray(forKey: "excludedQuickScanPaths") ?? [])
        )
        let sanitized = sanitizedQuickScanConfiguration(configuration)
        if sanitized.includedPaths != configuration.includedPaths ||
            sanitized.excludedPaths != configuration.excludedPaths {
            saveQuickScanConfiguration(sanitized)
        }
        return sanitized
    }

    nonisolated private static func sanitizedQuickScanConfiguration(
        _ configuration: QuickScanConfiguration
    ) -> QuickScanConfiguration {
        QuickScanConfiguration(
            includedPaths: configuration.includedPaths.filter { !DiskScanExclusions.contains(path: $0) },
            excludedPaths: configuration.excludedPaths.filter { !DiskScanExclusions.contains(path: $0) }
        )
    }

    nonisolated private static func saveQuickScanConfiguration(_ configuration: QuickScanConfiguration) {
        let defaults = UserDefaults.standard
        defaults.set(configuration.includedPaths.sorted(), forKey: "includedQuickScanPaths")
        defaults.set(configuration.excludedPaths.sorted(), forKey: "excludedQuickScanPaths")
    }

    nonisolated private static func removeLegacyScanCache() {
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let cacheDirectory = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/KleanBytes")
            let legacyNames = [
                "index.sqlite",
                "index.sqlite-shm",
                "index.sqlite-wal",
                "scan-snapshot.plist",
                "scan-snapshot-v2.plist"
            ]

            for name in legacyNames {
                let url = cacheDirectory.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
