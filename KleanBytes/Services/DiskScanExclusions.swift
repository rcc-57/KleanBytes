import Foundation

enum DiskScanExclusions {
    nonisolated private static let fixedPaths: Set<String> = [
        "/Volumes",
        "/Network",
        "/net",
        "/home",
        "/dev",
        "/.nofollow",
        "/System/Volumes/Data"
    ]

    nonisolated static func contains(_ url: URL) -> Bool {
        contains(path: url.path) || contains(path: url.standardizedFileURL.path)
    }

    nonisolated static func contains(path: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return excludedRoots.contains { root in
            normalizedPath == root || normalizedPath.hasPrefix(root + "/")
        }
    }

    nonisolated private static var excludedRoots: Set<String> {
        var paths = fixedPaths
        paths.insert(
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/KleanBytes")
                .standardizedFileURL.path
        )
        return paths
    }
}
