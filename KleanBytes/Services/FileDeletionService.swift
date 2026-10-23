import AppKit
import Foundation

enum DeletionSafetyError: LocalizedError {
    case protectedItem(String)

    var errorDescription: String? {
        switch self {
        case .protectedItem(let reason):
            "Объект нельзя удалить: \(reason)"
        }
    }
}

struct FileDeletionService {
    private let privilegedService = PrivilegedDeletionService()

    func makePlan(for nodes: [FileSystemNode]) async -> SecureDeletionPlan {
        await privilegedService.makePlan(
            for: nodes.map(\.url),
            warningURLs: Set(nodes.filter { $0.accessPolicy.showsLock }.map(\.url))
        )
    }

    func permanentlyDelete(_ plan: SecureDeletionPlan) async throws -> SecureDeletionResult {
        try await privilegedService.delete(plan)
    }

    func trash(_ node: FileSystemNode) throws {
        try trash(node.url)
    }

    func trash(_ url: URL) throws {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = standardized.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let bundle = Bundle.main.bundleURL.standardizedFileURL.path
        guard path != "/", path != home, path != bundle,
              !path.hasPrefix("/System/") else {
            throw DeletionSafetyError.protectedItem("системная область защищена")
        }
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}
