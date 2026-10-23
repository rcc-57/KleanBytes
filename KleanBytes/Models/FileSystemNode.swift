import Foundation

enum NodeScanStatus: String, Codable, Sendable {
    case complete
    case inaccessible
    case partiallyAccessible
}

struct FileSystemNode: Identifiable, Hashable, Codable, Sendable {
    let id: URL
    let name: String
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64
    let children: [FileSystemNode]
    let fileCount: Int
    let directoryCount: Int
    let isAccessible: Bool
    let scanStatus: NodeScanStatus

    var accessPolicy: FileAccessPolicy { FileAccessPolicy.classify(url, isDirectory: isDirectory) }
    var isInSystemArea: Bool { FileAccessPolicy.isSystemArea(url) }
    var presentation: FileItemPresentation? { FileItemPresentation.forURL(url) }
    var isHidden: Bool { name.hasPrefix(".") }
    var containedObjectCount: Int {
        isDirectory ? fileCount + max(0, directoryCount - 1) : 0
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var sortedChildren: [FileSystemNode] {
        children.sorted {
            if $0.size == $1.size { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.size > $1.size
        }
    }
}

enum FileItemBadge {
    case asset(String)
    case systemSymbol(String)
}

struct FileItemPresentation {
    let badge: FileItemBadge
    let title: String
    let message: String

    static func forURL(_ url: URL) -> FileItemPresentation? {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let library = home + "/Library"
        let applicationSupport = library + "/Application Support"

        if samePath(path, applicationSupport + "/MobileSync") {
            return FileItemPresentation(
                badge: .systemSymbol("iphone"),
                title: "Резервные копии iPhone и iPad",
                message: "Здесь хранятся резервные копии устройств. Для управления ими подключите устройство к Mac и откройте его в Finder."
            )
        }

        let managedApps: [(String, String, String)] = [
            ("Mail", "SystemAppMail", "Почта"),
            ("Safari", "SystemAppSafari", "Safari"),
            ("SafariSandboxBroker", "SystemAppSafari", "Safari"),
            ("SafariSafeBrowsing", "SystemAppSafari", "Safari"),
            ("Messages", "SystemAppMessages", "Сообщения"),
            ("Photos", "SystemAppPhotos", "Фото"),
            ("Shortcuts", "SystemAppShortcuts", "Команды"),
            ("Weather", "SystemAppWeather", "Погода"),
            ("Contacts", "SystemAppContacts", "Контакты"),
            ("Reminders", "SystemAppReminders", "Напоминания"),
            ("Calendars", "SystemAppCalendar", "Календарь")
        ]
        for (folder, assetName, appName) in managedApps where samePath(path, library + "/" + folder) {
            return FileItemPresentation(
                badge: .asset(assetName),
                title: "Данные приложения «\(appName)»",
                message: "Этими данными следует управлять через соответствующее приложение."
            )
        }
        if samePath(path, library + "/Spotlight") {
            return FileItemPresentation(
                badge: .systemSymbol("magnifyingglass"),
                title: "Данные Spotlight",
                message: "При проблемах с поиском используйте штатное переиндексирование Spotlight, а не удаляйте эти файлы вручную."
            )
        }
        if samePath(path, library + "/Cookies") {
            return FileItemPresentation(
                badge: .systemSymbol("cookie.fill"),
                title: "Cookies Safari",
                message: "Управляйте cookies и данными сайтов через Safari → Настройки → Конфиденциальность."
            )
        }
        return nil
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

}
