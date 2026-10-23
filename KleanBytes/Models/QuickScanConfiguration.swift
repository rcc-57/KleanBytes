import Foundation

enum QuickScanMembership: Sendable, Equatable {
    case included
    case excluded
    case mixed
}

struct QuickScanConfiguration: Sendable, Equatable {
    static let minimumDefaultSize: Int64 = 1_048_576
    var includedPaths: Set<String>
    var excludedPaths: Set<String>

    nonisolated static let empty = QuickScanConfiguration(includedPaths: [], excludedPaths: [])

    func includes(_ url: URL) -> Bool {
        includes(path: url.standardizedFileURL.path)
    }

    func includes(_ node: FileSystemNode) -> Bool {
        let path = node.url.standardizedFileURL.path
        if hasExplicitRule(for: path) {
            return includes(path: path)
        }
        if node.accessPolicy.showsLock { return false }
        if node.size < Self.minimumDefaultSize && !isInsideRootApplications(path) { return false }
        return true
    }

    func shouldTraverse(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if includes(path: path) {
            return true
        }
        return hasIncludedDescendant(of: url)
    }

    func hasIncludedDescendant(of url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let prefix = path == "/" ? "/" : path + "/"
        return includedPaths.contains { $0.hasPrefix(prefix) }
    }

    func membership(of node: FileSystemNode) -> QuickScanMembership {
        let path = node.url.standardizedFileURL.path
        let isIncluded = includes(node)
        guard node.isDirectory else {
            return isIncluded ? .included : .excluded
        }

        let prefix = path == "/" ? "/" : path + "/"
        let descendantRules = includedPaths.union(excludedPaths).filter {
            $0 != path && $0.hasPrefix(prefix)
        }
        let hasOppositeDescendant = descendantRules.contains {
            includes(path: $0) != isIncluded
        }

        if hasOppositeDescendant {
            return .mixed
        }
        return isIncluded ? .included : .excluded
    }

    mutating func toggle(_ node: FileSystemNode) {
        let path = node.url.standardizedFileURL.path
        let currentMembership = membership(of: node)

        removeRules(inside: path)
        switch currentMembership {
        case .included:
            excludedPaths.insert(path)
        case .excluded, .mixed:
            includedPaths.insert(path)
        }
    }

    private func includes(path: String) -> Bool {
        let matchingIncluded = mostSpecificRule(in: includedPaths, for: path)
        let matchingExcluded = mostSpecificRule(in: excludedPaths, for: path)

        switch (matchingIncluded, matchingExcluded) {
        case let (included?, excluded?):
            return included.count > excluded.count
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return defaultIncludes(path: path)
        }
    }

    private func mostSpecificRule(in rules: Set<String>, for path: String) -> String? {
        rules
            .filter { path == $0 || path.hasPrefix($0 + "/") }
            .max { $0.count < $1.count }
    }

    private func defaultIncludes(path: String) -> Bool {
        !FileAccessPolicy.classify(URL(fileURLWithPath: path)).showsLock
    }

    private func hasExplicitRule(for path: String) -> Bool {
        mostSpecificRule(in: includedPaths, for: path) != nil ||
        mostSpecificRule(in: excludedPaths, for: path) != nil
    }

    private func isInsideRootApplications(_ path: String) -> Bool {
        path == "/Applications" || path.hasPrefix("/Applications/")
    }

    private mutating func removeRules(inside path: String) {
        let prefix = path == "/" ? "/" : path + "/"
        includedPaths = includedPaths.filter { $0 != path && !$0.hasPrefix(prefix) }
        excludedPaths = excludedPaths.filter { $0 != path && !$0.hasPrefix(prefix) }
    }
}
