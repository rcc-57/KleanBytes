import Foundation

enum DiskSpaceService {
    static func volume(for url: URL = URL(fileURLWithPath: "/")) throws -> DiskVolume {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIdentifierKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskVolume(
            url: url,
            identifier: values.volumeIdentifier.map { String(describing: $0) } ?? url.path,
            name: values.volumeName ?? url.lastPathComponent.nonEmpty ?? "Macintosh HD",
            totalCapacity: total,
            availableCapacity: available
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
