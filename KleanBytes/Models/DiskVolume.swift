import Foundation

struct DiskVolume: Sendable {
    let url: URL
    let identifier: String
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64

    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    var fractionUsed: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(max(Double(usedCapacity) / Double(totalCapacity), 0), 1)
    }
}
