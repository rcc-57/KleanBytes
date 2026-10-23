import Foundation

struct SelectedFileItem: Identifiable, Hashable, Sendable {
    let id: URL
    let name: String
    let url: URL
    let size: Int64
    let isDirectory: Bool
    let objectCount: Int

    init(node: FileSystemNode) {
        id = node.id
        name = node.name
        url = node.url
        size = node.size
        isDirectory = node.isDirectory
        objectCount = node.containedObjectCount
    }
}
