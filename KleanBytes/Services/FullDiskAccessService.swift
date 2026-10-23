import Foundation

enum FullDiskAccessService {
    nonisolated static func isGranted() -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let protectedLocations = [
            home.appendingPathComponent("Library/Safari", isDirectory: true),
            home.appendingPathComponent("Library/Mail", isDirectory: true),
            home.appendingPathComponent("Library/Messages", isDirectory: true)
        ]
        let fileManager = FileManager.default

        for location in protectedLocations where fileManager.fileExists(atPath: location.path) {
            do {
                _ = try fileManager.contentsOfDirectory(
                    at: location,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                return true
            } catch {
                continue
            }
        }
        return false
    }
}
