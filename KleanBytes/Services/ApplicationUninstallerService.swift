import AppKit
import Foundation
import Security

enum ApplicationUninstallerError: LocalizedError {
    case invalidApplication
    case protectedApplication
    case nothingSelected

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            "Выбранный объект не является корректным приложением macOS."
        case .protectedApplication:
            "KleanBytes не удаляет системные приложения или собственный пакет приложения."
        case .nothingSelected:
            "Не выбрано ни одного объекта для удаления."
        }
    }
}

actor ApplicationUninstallerService {
    private struct ApplicationIdentity {
        var identifiers: Set<String>
        var appGroups: Set<String>
        var names: Set<String>
        let teamIdentifier: String?
        let primaryIdentifier: String

        var exactTokens: Set<String> {
            Set((identifiers.union(appGroups)).map { $0.lowercased() })
        }
    }

    private let fileManager = FileManager.default
    private let deletionService = PrivilegedDeletionService()
    private var indexedRelatedFiles: [(URL, ApplicationRelatedItem.Category)]?

    func installedApplications() -> [InstalledApplication] {
            let roots = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent("Applications", isDirectory: true)
            ]
            var applications: [InstalledApplication] = []
            var seen = Set<String>()

            for root in roots where fileManager.fileExists(atPath: root.path) {
                let topLevelURLs = (try? fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                let installationDirectories = topLevelURLs.filter(isInstallationDirectory)

                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for case let url as URL in enumerator {
                    guard url.pathExtension.lowercased() == "app" else { continue }
                    enumerator.skipDescendants()
                    let standardized = url.standardizedFileURL
                    guard seen.insert(standardized.path).inserted,
                          standardized != Bundle.main.bundleURL.standardizedFileURL,
                          let bundle = Bundle(url: standardized),
                          let identifier = bundle.bundleIdentifier,
                          !identifier.isEmpty else { continue }

                    applications.append(
                        InstalledApplication(
                            id: standardized,
                            name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                                ?? standardized.deletingPathExtension().lastPathComponent,
                            url: standardized,
                            bundleIdentifier: identifier,
                            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                            size: allocatedSize(of: standardized)
                        )
                    )
                }

                let discoveredApplicationPaths = applications
                    .filter { $0.url.pathExtension.lowercased() == "app" }
                    .map { $0.url.standardizedFileURL.path }
                for url in installationDirectories {
                    let standardized = url.standardizedFileURL
                    let containsDiscoveredApplication = discoveredApplicationPaths.contains {
                        $0.hasPrefix(standardized.path + "/")
                    }
                    guard !containsDiscoveredApplication,
                          seen.insert(standardized.path).inserted else { continue }
                    applications.append(installationDirectoryApplication(at: standardized))
                }
            }

            return applications.sorted {
                if $0.size == $1.size {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.size > $1.size
            }
    }

    private func isInstallationDirectory(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() != "app",
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func installationDirectoryApplication(at url: URL) -> InstalledApplication {
        InstalledApplication(
            id: url,
            name: url.lastPathComponent,
            url: url,
            bundleIdentifier: firstBundleIdentifier(in: url) ?? syntheticIdentifier(for: url),
            version: nil,
            size: allocatedSize(of: url)
        )
    }

    private func firstBundleIdentifier(in directory: URL) -> String? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
            enumerator.skipDescendants()
            if let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty {
                return identifier
            }
        }
        return nil
    }

    private func syntheticIdentifier(for url: URL) -> String {
        let identity = url.lastPathComponent
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "." }
            .joined()
        return "directory.\(identity)"
    }

    func plan(for application: InstalledApplication) throws -> ApplicationUninstallPlan {
            let homeLibrary = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
            let identifier = application.bundleIdentifier
            let name = application.name
            let identity = applicationIdentity(for: application)
            var candidates: [(URL, ApplicationRelatedItem.Category)] = [
                (homeLibrary.appendingPathComponent("Application Support/\(identifier)"), .applicationSupport),
                (homeLibrary.appendingPathComponent("Application Support/\(name)"), .applicationSupport),
                (homeLibrary.appendingPathComponent("Caches/\(identifier)"), .cache),
                (homeLibrary.appendingPathComponent("Caches/\(name)"), .cache),
                (homeLibrary.appendingPathComponent("Preferences/\(identifier).plist"), .preferences),
                (homeLibrary.appendingPathComponent("Saved Application State/\(identifier).savedState"), .savedState),
                (homeLibrary.appendingPathComponent("HTTPStorages/\(identifier)"), .webData),
                (homeLibrary.appendingPathComponent("WebKit/\(identifier)"), .webData),
                (homeLibrary.appendingPathComponent("Containers/\(identifier)"), .applicationSupport),
                (homeLibrary.appendingPathComponent("Logs/\(identifier)"), .logs),
                (homeLibrary.appendingPathComponent("Logs/\(name)"), .logs),
                (homeLibrary.appendingPathComponent("LaunchAgents/\(identifier).plist"), .loginItem),
                (URL(fileURLWithPath: "/Library/Application Support/\(identifier)"), .applicationSupport),
                (URL(fileURLWithPath: "/Library/LaunchAgents/\(identifier).plist"), .loginItem),
                (URL(fileURLWithPath: "/Library/LaunchDaemons/\(identifier).plist"), .loginItem),
                (URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(identifier)"), .helper)
            ]

            for relatedIdentifier in identity.identifiers.union(identity.appGroups) {
                candidates.append(contentsOf: directCandidates(
                    identifier: relatedIdentifier,
                    homeLibrary: homeLibrary
                ))
            }
            candidates.append(contentsOf: relatedFileIndex().filter { url, _ in
                isRelatedCandidate(url, identity: identity)
            })

            if identifier == "com.apple.dt.Xcode" {
                candidates.append(contentsOf: coreSimulatorItems(in: homeLibrary))
            }

            var seen = Set<String>()
            let related = candidates
                .sorted { $0.0.pathComponents.count < $1.0.pathComponents.count }
                .compactMap { url, category -> ApplicationRelatedItem? in
                let standardized = url.standardizedFileURL
                guard seen.insert(standardized.path).inserted,
                      fileManager.fileExists(atPath: standardized.path),
                      !seen.contains(where: { existingPath in
                          existingPath != standardized.path
                              && standardized.path.hasPrefix(existingPath + "/")
                      }) else { return nil }
                return ApplicationRelatedItem(
                    id: standardized,
                    url: standardized,
                    category: category,
                    size: 0
                )
                }
                .sorted { $0.size > $1.size }

            return ApplicationUninstallPlan(
                application: application,
                relatedItems: related,
                requiresVendorUninstaller: hasVendorManagedComponents(
                    application: application,
                    relatedItems: related
                )
            )
    }

    private func coreSimulatorItems(
        in homeLibrary: URL
    ) -> [(URL, ApplicationRelatedItem.Category)] {
        let root = homeLibrary.appendingPathComponent("Developer/CoreSimulator", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let children = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return children.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]), values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true else {
                return nil
            }
            return (url.standardizedFileURL, .developerData)
        }
    }

    func size(of url: URL) async -> Int64 {
        let measurement = Task.detached(priority: .utility) {
            Self.allocatedSizeInBackground(of: url)
        }
        return await withTaskCancellationHandler {
            await measurement.value
        } onCancel: {
            measurement.cancel()
        }
    }

    func runningApplicationNames(for plan: ApplicationUninstallPlan) -> [String] {
        let identifiers = bundleIdentifiers(
            in: plan.application.url,
            primary: plan.application.bundleIdentifier
        )
        let names = identifiers.flatMap { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        }
        .compactMap(\.localizedName)
        return Array(Set(names)).sorted()
    }

    func terminateRunningApplications(for plan: ApplicationUninstallPlan) async -> Bool {
        let identifiers = bundleIdentifiers(
            in: plan.application.url,
            primary: plan.application.bundleIdentifier
        )
        let applications = identifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        applications.forEach { _ = $0.terminate() }

        for _ in 0..<30 {
            if applications.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return applications.allSatisfy(\.isTerminated)
    }

    func permanentlyDelete(
        plan: ApplicationUninstallPlan,
        removeApplication: Bool,
        selectedRelatedIDs: Set<URL>
    ) async throws -> ApplicationUninstallResult {
        try validate(plan.application)

        let selectedRelated = plan.relatedItems.filter { selectedRelatedIDs.contains($0.id) }
        let urls = selectedRelated.map(\.url) + (removeApplication ? [plan.application.url] : [])
        guard !urls.isEmpty else { throw ApplicationUninstallerError.nothingSelected }

        for url in urls {
            try validateDeletionTarget(url, application: plan.application)
        }
        let deletionPlan = await deletionService.makePlan(for: urls)
        let result = try await deletionService.delete(deletionPlan)
        return ApplicationUninstallResult(
            removedURLs: result.removedURLs,
            failures: result.failures.map { "\($0.url.path): \($0.reason)" }
        )
    }

    private func validate(_ application: InstalledApplication) throws {
        let path = application.url.standardizedFileURL.path
        let isApplicationBundle = application.url.pathExtension.lowercased() == "app"
        let isTopLevelInstallationDirectory = application.url.pathExtension.isEmpty
            && ["/Applications", NSHomeDirectory() + "/Applications"].contains(
                application.url.deletingLastPathComponent().standardizedFileURL.path
            )
        guard isApplicationBundle || isTopLevelInstallationDirectory,
              path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") else {
            throw ApplicationUninstallerError.invalidApplication
        }
        guard !path.hasPrefix("/System/"),
              application.url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else {
            throw ApplicationUninstallerError.protectedApplication
        }
    }

    private func hasVendorManagedComponents(
        application: InstalledApplication,
        relatedItems: [ApplicationRelatedItem]
    ) -> Bool {
        let suspiciousNames = ["uninstall", "uninstaller", "remove", "maintenance"]
        if let enumerator = fileManager.enumerator(
            at: application.url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            var inspected = 0
            for case let child as URL in enumerator {
                inspected += 1
                if inspected > 2_000 { break }
                let name = child.deletingPathExtension().lastPathComponent.lowercased()
                if suspiciousNames.contains(where: name.contains) { return true }
                let path = child.path.lowercased()
                if path.contains("/contents/library/systemextensions/")
                    || path.contains("/contents/library/driverextensions/") {
                    return true
                }
            }
        }
        return relatedItems.contains { item in
            item.category == .helper || item.category == .loginItem
        }
    }

    private func validateDeletionTarget(_ url: URL, application: InstalledApplication) throws {
        let path = url.standardizedFileURL.path
        let homeLibrary = NSHomeDirectory() + "/Library/"
        let allowedSystemRoots = [
            "/Library/Application Support/",
            "/Library/Caches/",
            "/Library/Preferences/",
            "/Library/Logs/",
            "/Library/LaunchAgents/",
            "/Library/LaunchDaemons/",
            "/Library/PrivilegedHelperTools/"
        ]
        let isApplication = path == application.url.standardizedFileURL.path
        let isAllowedRelated = path.hasPrefix(homeLibrary)
            || allowedSystemRoots.contains(where: { path.hasPrefix($0) })
        guard isApplication || isAllowedRelated else {
            throw ApplicationUninstallerError.protectedApplication
        }
        guard path != NSHomeDirectory(), path != "/", !path.hasPrefix("/System/") else {
            throw ApplicationUninstallerError.protectedApplication
        }
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey, .fileSizeKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true || values.isSymbolicLink == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(forKeys: keys),
                  childValues.isSymbolicLink != true,
                  childValues.isRegularFile == true else { continue }
            total += Int64(
                childValues.totalFileAllocatedSize
                ?? childValues.fileAllocatedSize
                ?? childValues.fileSize
                ?? 0
            )
        }
        return total
    }

    private func relatedFileIndex() -> [(URL, ApplicationRelatedItem.Category)] {
        if let indexedRelatedFiles {
            return indexedRelatedFiles
        }

        let homeLibrary = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        let roots: [(URL, ApplicationRelatedItem.Category)] = [
            (homeLibrary.appendingPathComponent("Application Support"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Caches"), .cache),
            (homeLibrary.appendingPathComponent("Preferences"), .preferences),
            (homeLibrary.appendingPathComponent("Saved Application State"), .savedState),
            (homeLibrary.appendingPathComponent("HTTPStorages"), .webData),
            (homeLibrary.appendingPathComponent("WebKit"), .webData),
            (homeLibrary.appendingPathComponent("Containers"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Group Containers"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Application Scripts"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Logs"), .logs),
            (homeLibrary.appendingPathComponent("LaunchAgents"), .loginItem),
            (homeLibrary.appendingPathComponent("Autosave Information"), .other),
            (homeLibrary.appendingPathComponent("Cookies"), .webData),
            (homeLibrary.appendingPathComponent("Developer"), .developerData),
            (homeLibrary.appendingPathComponent("Installers"), .installer),
            (URL(fileURLWithPath: "/Library/Application Support"), .applicationSupport),
            (URL(fileURLWithPath: "/Library/Caches"), .cache),
            (URL(fileURLWithPath: "/Library/Preferences"), .preferences),
            (URL(fileURLWithPath: "/Library/Logs"), .logs),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .loginItem),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .loginItem),
            (URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), .helper)
        ]

        var index: [(URL, ApplicationRelatedItem.Category)] = []
        for (root, category) in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                index.append((url.standardizedFileURL, category))
                if url.pathComponents.count - root.pathComponents.count >= 3,
                   (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
            }
        }

        indexedRelatedFiles = index
        return index
    }

    private func isRelatedCandidate(_ url: URL, identity: ApplicationIdentity) -> Bool {
        let fileName = url.lastPathComponent
        let lowercasedName = fileName.lowercased()
        let canonicalName = canonicalIdentity(fileName)

        if identity.exactTokens.contains(where: {
            identifierToken($0, matches: lowercasedName)
                || canonicalName == canonicalIdentity($0)
        }) {
            return true
        }

        let pathComponents = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        if pathComponents.contains(where: identity.exactTokens.contains) {
            return true
        }

        let fullNameMatches = identity.names.map(canonicalIdentity).contains { fullName in
            fullName.count >= 4 && canonicalName.contains(fullName)
        }
        guard fullNameMatches || productNameAnchors(identity).contains(where: {
            productAnchor($0, matches: fileName)
        }) else {
            return false
        }

        let applicationVersions = numericVersionTokens(in: identity.names.joined(separator: " "))
        let candidateVersions = numericVersionTokens(in: fileName)
        return applicationVersions.isEmpty
            || candidateVersions.isEmpty
            || !applicationVersions.isDisjoint(with: candidateVersions)
    }

    private func productNameAnchors(_ identity: ApplicationIdentity) -> Set<String> {
        let ignored: Set<String> = [
            "app", "application", "pro", "studio", "desktop", "client", "helper",
            "service", "agent", "mac", "macos", "osx"
        ]
        let identifierParts = Set(
            identity.primaryIdentifier
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .dropLast()
        )
        let separators = CharacterSet.alphanumerics.inverted
        return Set(identity.names.flatMap { name in
            name
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: separators)
                .filter {
                    $0.count >= 4
                        && !$0.allSatisfy(\.isNumber)
                        && !ignored.contains($0)
                        && !identifierParts.contains($0)
                }
                .map(canonicalIdentity)
        })
    }

    private func numericVersionTokens(in value: String) -> Set<String> {
        Set(
            value.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count == 4 && $0.allSatisfy(\.isNumber) }
        )
    }

    private func productAnchor(_ anchor: String, matches value: String) -> Bool {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        var searchStart = folded.startIndex
        while searchStart < folded.endIndex,
              let range = folded.range(
                of: anchor,
                options: [],
                range: searchStart..<folded.endIndex
            ) {
            if range.upperBound == folded.endIndex { return true }
            let next = folded[range.upperBound]
            if !next.isLetter && !next.isNumber {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private func directCandidates(
        identifier: String,
        homeLibrary: URL
    ) -> [(URL, ApplicationRelatedItem.Category)] {
        [
            (homeLibrary.appendingPathComponent("Application Support/\(identifier)"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Caches/\(identifier)"), .cache),
            (homeLibrary.appendingPathComponent("Preferences/\(identifier).plist"), .preferences),
            (homeLibrary.appendingPathComponent("Saved Application State/\(identifier).savedState"), .savedState),
            (homeLibrary.appendingPathComponent("HTTPStorages/\(identifier)"), .webData),
            (homeLibrary.appendingPathComponent("WebKit/\(identifier)"), .webData),
            (homeLibrary.appendingPathComponent("Containers/\(identifier)"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Group Containers/\(identifier)"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Application Scripts/\(identifier)"), .applicationSupport),
            (homeLibrary.appendingPathComponent("Logs/\(identifier)"), .logs),
            (homeLibrary.appendingPathComponent("LaunchAgents/\(identifier).plist"), .loginItem),
            (homeLibrary.appendingPathComponent("Installers/\(identifier)"), .installer),
            (URL(fileURLWithPath: "/Library/Application Support/\(identifier)"), .applicationSupport),
            (URL(fileURLWithPath: "/Library/LaunchAgents/\(identifier).plist"), .loginItem),
            (URL(fileURLWithPath: "/Library/LaunchDaemons/\(identifier).plist"), .loginItem),
            (URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(identifier)"), .helper)
        ]
    }

    private func applicationIdentityAnchors(
        name: String,
        primaryIdentifier: String
    ) -> Set<String> {
        let ignoredTokens: Set<String> = [
            "app", "application", "com", "org", "net", "io", "co", "apple",
            "mac", "macos", "osx", "helper", "service", "agent", "xpc", "pro",
            "studio", "desktop", "client", "chat"
        ]
        let separators = CharacterSet.alphanumerics.inverted
        let normalizedName = name
            .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let nameWords = normalizedName.components(separatedBy: separators)
        let meaningfulNameWords = nameWords.filter {
            $0.count >= 4 && !ignoredTokens.contains($0)
        }
        let identifierWords = primaryIdentifier.lowercased().components(separatedBy: separators)

        var anchors: Set<String> = [canonicalIdentity(normalizedName)]
        if let identifierAnchor = identifierWords.last(where: {
            $0.count >= 5 && !ignoredTokens.contains($0)
        }) {
            anchors.insert(canonicalIdentity(identifierAnchor))
        }
        if meaningfulNameWords.count == 1,
           let onlyNameWord = meaningfulNameWords.first {
            anchors.insert(canonicalIdentity(onlyNameWord))
        } else if nameWords.contains(where: { ignoredTokens.contains($0) }),
                  let productName = meaningfulNameWords.last {
            anchors.insert(canonicalIdentity(productName))
        }
        return anchors.filter { $0.count >= 4 }
    }

    private func canonicalIdentity(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func applicationIdentity(for application: InstalledApplication) -> ApplicationIdentity {
        let primarySigning = signingMetadata(for: application.url)
        var identity = ApplicationIdentity(
            identifiers: [application.bundleIdentifier],
            appGroups: primarySigning.appGroups,
            names: [application.name],
            teamIdentifier: primarySigning.teamIdentifier,
            primaryIdentifier: application.bundleIdentifier
        )

        if let bundle = Bundle(url: application.url) {
            addBundleMetadata(bundle, to: &identity)
        }

        // Executable bundles are sealed by the outer application's signature. Reading signing
        // information for every nested plug-in is extremely expensive for large applications.
        let bundleExtensions: Set<String> = ["app", "appex", "xpc"]
        guard let enumerator = fileManager.enumerator(
            at: application.url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return identity }

        for case let url as URL in enumerator
        where bundleExtensions.contains(url.pathExtension.lowercased()) {
            defer { enumerator.skipDescendants() }
            guard let bundle = Bundle(url: url),
                  let identifier = bundle.bundleIdentifier else { continue }

            identity.identifiers.insert(identifier)
            addBundleMetadata(bundle, to: &identity)
        }
        return identity
    }

    nonisolated private static func allocatedSizeInBackground(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey, .fileSizeKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true || values.isSymbolicLink == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            if Task.isCancelled { return total }
            guard let childValues = try? child.resourceValues(forKeys: keys),
                  childValues.isSymbolicLink != true,
                  childValues.isRegularFile == true else { continue }
            total += Int64(
                childValues.totalFileAllocatedSize
                    ?? childValues.fileAllocatedSize
                    ?? childValues.fileSize
                    ?? 0
            )
        }
        return total
    }

    private func addBundleMetadata(_ bundle: Bundle, to identity: inout ApplicationIdentity) {
        if let identifier = bundle.bundleIdentifier {
            identity.identifiers.insert(identifier)
        }
        if let helpers = bundle.object(forInfoDictionaryKey: "SMPrivilegedExecutables")
            as? [String: Any] {
            identity.identifiers.formUnion(helpers.keys)
        }
    }

    private func signingMetadata(
        for bundleURL: URL
    ) -> (teamIdentifier: String?, appGroups: Set<String>) {
        let executableURL = Bundle(url: bundleURL)?.executableURL ?? bundleURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return (nil, [])
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let dictionary = information as? [String: Any] else {
            return (nil, [])
        }

        let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return (teamIdentifier, Set(groups))
    }

    private func bundleIdentifiers(in applicationURL: URL, primary: String) -> Set<String> {
        let name = Bundle(url: applicationURL)?
            .object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let application = InstalledApplication(
            id: applicationURL,
            name: name,
            url: applicationURL,
            bundleIdentifier: primary,
            version: nil,
            size: 0
        )
        return applicationIdentity(for: application).identifiers
    }

    private func owns(identifier: String, primaryIdentifier: String) -> Bool {
        let identifier = identifier.lowercased()
        let primary = primaryIdentifier.lowercased()
        return identifier == primary
            || identifier.hasPrefix(primary + ".")
            || identifier.hasPrefix(primary + "-")
    }

    private func identifierToken(_ identifier: String, matches fileName: String) -> Bool {
        let stem = fileName
            .replacingOccurrences(of: ".plist", with: "")
            .replacingOccurrences(of: ".savedState", with: "")
            .replacingOccurrences(of: ".binarycookies", with: "")
        return stem == identifier
            || stem.hasPrefix(identifier + ".")
            || stem.hasSuffix("+" + identifier)
    }
}
