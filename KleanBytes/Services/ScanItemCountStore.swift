import Foundation

struct ScanItemCounts: Codable, Sendable {
    var full: Int?
    var quick: Int?
}

struct ScanItemCountStore: Sendable {
    private let fileManager = FileManager.default

    func itemCount(for mode: DiskScanMode) -> Int? {
        guard let fileURL = try? storageURL() else { return nil }
        let counts = load(from: fileURL)

        switch mode {
        case .full:
            return counts.full
        case .quick:
            return counts.quick
        }
    }

    func save(_ itemCount: Int, for mode: DiskScanMode) throws {
        let fileURL = try storageURL()
        var counts = load(from: fileURL)

        switch mode {
        case .full:
            counts.full = itemCount
        case .quick:
            counts.quick = itemCount
        }

        let data = try JSONEncoder().encode(counts)
        try data.write(to: fileURL, options: .atomic)
    }

    private func load(from fileURL: URL) -> ScanItemCounts {
        guard let data = try? Data(contentsOf: fileURL),
              let counts = try? JSONDecoder().decode(ScanItemCounts.self, from: data) else {
            return ScanItemCounts()
        }
        return counts
    }

    private func storageURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/KleanBytes", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("scan-item-counts.json")
    }
}
