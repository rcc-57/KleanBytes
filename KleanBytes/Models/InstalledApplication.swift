import Foundation

struct InstalledApplication: Identifiable, Hashable, Sendable {
    let id: URL
    let name: String
    let url: URL
    let bundleIdentifier: String
    let version: String?
    let size: Int64
}

struct ApplicationRelatedItem: Identifiable, Hashable, Sendable {
    enum Category: String, Sendable {
        case applicationSupport = "Application Support"
        case cache = "Кэш"
        case preferences = "Настройки"
        case savedState = "Сохранённое состояние"
        case webData = "Веб-данные"
        case logs = "Журналы"
        case loginItem = "Фоновый компонент"
        case helper = "Вспомогательный компонент"
        case developerData = "Данные разработчика"
        case installer = "Установщики"
        case other = "Связанные данные"
    }

    let id: URL
    let url: URL
    let category: Category
    let size: Int64
    let isSizeCalculated: Bool

    nonisolated init(
        id: URL,
        url: URL,
        category: Category,
        size: Int64,
        isSizeCalculated: Bool = false
    ) {
        self.id = id
        self.url = url
        self.category = category
        self.size = size
        self.isSizeCalculated = isSizeCalculated
    }
}

struct ApplicationUninstallPlan: Sendable {
    let application: InstalledApplication
    let relatedItems: [ApplicationRelatedItem]
    let requiresVendorUninstaller: Bool

    var totalSize: Int64 {
        application.size + relatedItems.reduce(0) { $0 + $1.size }
    }
}

struct ApplicationUninstallResult: Sendable {
    let removedURLs: [URL]
    let failures: [String]

    var succeeded: Bool { failures.isEmpty }
}
