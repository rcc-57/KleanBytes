import Foundation

enum ByteSizeFormatter {
    static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func string(from bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
