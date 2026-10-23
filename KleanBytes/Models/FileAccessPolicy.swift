import Foundation

enum FileAccessPolicy: Sendable {
    case regular
    case topLevelFolder
    case selectionDisabled
    case applicationsDirectory
    case libraryWarning
    case libraryFolderWarning
    case applicationContent
    case systemProtected
    case companionSystem
    case personalProtected
    case finderManagedBackup
    case safariManaged
    case packageManaged
    case packageContent
    case userFolderWarning
    case userFileWarning

    var isSelectable: Bool {
        switch self {
        case .regular, .libraryWarning, .applicationContent, .packageContent, .userFileWarning:
            true
        case .topLevelFolder, .selectionDisabled, .applicationsDirectory, .libraryFolderWarning, .systemProtected,
             .companionSystem, .personalProtected, .finderManagedBackup, .safariManaged,
             .packageManaged, .userFolderWarning:
            false
        }
    }

    var showsLock: Bool {
        switch self {
        case .systemProtected, .companionSystem, .personalProtected,
             .finderManagedBackup, .safariManaged:
            true
        case .regular, .topLevelFolder, .selectionDisabled, .applicationsDirectory, .libraryWarning,
             .libraryFolderWarning, .applicationContent, .packageManaged,
             .packageContent, .userFolderWarning, .userFileWarning:
            false
        }
    }

    var showsWarning: Bool {
        switch self {
        case .libraryWarning, .libraryFolderWarning, .packageManaged,
             .packageContent, .userFolderWarning, .userFileWarning:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .regular:
            "Файл или папка"
        case .topLevelFolder:
            "Верхнеуровневая папка"
        case .selectionDisabled:
            "Служебная пользовательская папка"
        case .applicationsDirectory:
            "Приложения"
        case .libraryWarning, .libraryFolderWarning:
            "Компоненты программ"
        case .applicationContent:
            "Приложение или компонент приложения"
        case .systemProtected:
            "Системный элемент macOS"
        case .companionSystem:
            "Сопутствующий системный файл"
        case .personalProtected:
            "Защищённые личные данные"
        case .finderManagedBackup:
            "Резервная копия устройства"
        case .safariManaged:
            "Данные Safari"
        case .packageManaged:
            "Папка управляемых компонентов"
        case .packageContent:
            "Компонент стороннего программного обеспечения"
        case .userFolderWarning:
            "Пользовательская папка-оболочка"
        case .userFileWarning:
            "Пользовательский конфигурационный файл"
        }
    }

    var message: String {
        switch self {
        case .regular:
            "Обычный файл или папка."
        case .topLevelFolder:
            "Верхнеуровневая папка."
        case .selectionDisabled:
            "Стандартная папка macOS или пользовательской среды. Откройте её, чтобы просмотреть содержимое."
        case .applicationsDirectory:
            "Используйте деинсталлятор."
        case .libraryWarning:
            "Здесь могут находиться компоненты установленных программ. Удаляйте данные только после удаления соответствующего ПО или если точно знаете их назначение. Предпочтительнее использовать штатный деинсталлятор."
        case .libraryFolderWarning:
            "Эта папка обслуживает macOS или установленные программы. Внутри могут находиться необходимые и неудаляемые компоненты."
        case .applicationContent:
            "Для удаления приложения и связанных с ним компонентов лучше использовать штатный деинсталлятор разработчика."
        case .systemProtected:
            "Это системный элемент macOS. Изменение его содержимого может нарушить работу системы."
        case .companionSystem:
            "Здесь находятся сопутствующие файлы системы и активных служб. Ручное удаление может нарушить работу macOS или установленных программ."
        case .personalProtected:
            "Здесь могут храниться личные данные, пароли, учётные записи, почта или синхронизируемые документы."
        case .finderManagedBackup:
            "Здесь находятся локальные резервные копии iPhone и iPad. Управляйте ими через Finder: подключите устройство и откройте «Управлять резервными копиями»."
        case .safariManaged:
            "Историю очищайте через Safari → История → Очистить историю. Cookies и данные сайтов — через Safari → Настройки → Конфиденциальность → Управлять данными веб-сайтов."
        case .packageManaged:
            "Здесь находятся компоненты сторонних программ или пакетных менеджеров. Перед очисткой проверьте их назначение."
        case .packageContent:
            "Этот объект относится к стороннему программному обеспечению. Если программа больше не нужна, предпочтительнее использовать её деинсталлятор или соответствующий пакетный менеджер."
        case .userFolderWarning:
            "Папка используется macOS или программами как постоянная оболочка. Внутри могут находиться важные настройки и пользовательские данные."
        case .userFileWarning:
            "Файл содержит пользовательские настройки или историю. После удаления соответствующие настройки или история будут потеряны."
        }
    }

    static func classify(_ url: URL, isDirectory: Bool? = nil) -> FileAccessPolicy {
        let policy = rawPolicy(for: url, isDirectory: isDirectory)
        return normalized(policy, isDirectory: isDirectory)
    }

    static func isSystemArea(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let roots = [
            "/System", "/bin", "/sbin", "/private", "/dev", "/cores",
            "/etc", "/var"
        ]
        if roots.contains(where: { insideInsensitive(path, root: $0) }) { return true }
        return insideInsensitive(path, root: "/usr")
            && !insideInsensitive(path, root: "/usr/local")
    }

    static func isApplicationsDirectory(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homeApplications = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path
        return samePath(path, "/Applications") || samePath(path, homeApplications)
    }

    /// UI invariant: a file is always actionable (checkbox) or protected (lock).
    /// Warning is an independent risk marker, but a protected item never shows it.
    private static func normalized(
        _ policy: FileAccessPolicy,
        isDirectory: Bool?
    ) -> FileAccessPolicy {
        guard isDirectory == false else { return policy }
        if policy.showsLock || policy.isSelectable { return policy }
        return policy.showsWarning ? .userFileWarning : .regular
    }

    private static func rawPolicy(for url: URL, isDirectory: Bool?) -> FileAccessPolicy {
        let path = url.standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path

        if path.lowercased() == "/.volumeicon.icns"
            || path.lowercased() == "/volumeicon.icns"
            || url.lastPathComponent.caseInsensitiveCompare(".DS_Store") == .orderedSame {
            return .systemProtected
        }

        if let sharedPolicy = sharedUserPolicy(for: path) {
            return sharedPolicy
        }
        if let homePolicy = userHomePolicy(for: path, home: home, isDirectory: isDirectory) {
            return homePolicy
        }

        if inside(path, root: home + "/Library/Application Support/MobileSync/Backup") {
            return .finderManagedBackup
        }
        if inside(path, root: home + "/Library/Safari")
            || inside(path, root: home + "/Library/Containers/com.apple.Safari")
            || inside(path, root: home + "/Library/WebKit") {
            return .safariManaged
        }

        let personalRoots = [
            home + "/Library/Keychains",
            home + "/Library/Mail",
            home + "/Library/Messages",
            home + "/Library/IdentityServices",
            home + "/Library/Accounts",
            home + "/Library/Preferences",
            home + "/Library/Group Containers",
            home + "/Library/Application Support/CloudDocs",
            home + "/Library/Mobile Documents",
            home + "/Library/CloudStorage",
            home + "/Library/Calendars",
            home + "/Library/AddressBook",
            home + "/Library/Application Support/com.apple.TCC",
            home + "/Pictures/Photos Library.photoslibrary"
        ]
        if personalRoots.contains(where: { inside(path, root: $0) }) {
            return .personalProtected
        }

        if inside(path, root: "/System") {
            return .systemProtected
        }

        if isApplicationsDirectory(url) {
            return .applicationsDirectory
        }
        if path == "/Users" || path == "/Library" {
            return .topLevelFolder
        }
        if inside(path, root: "/Applications") {
            return .applicationContent
        }
        if inside(path, root: "/Library") {
            return libraryPolicy(for: path, isDirectory: isDirectory)
        }

        if path == "/opt" {
            return .packageManaged
        }
        if inside(path, root: "/opt") {
            return .packageContent
        }

        if path == "/usr" || path == "/usr/local" {
            return .packageManaged
        }
        if inside(path, root: "/usr/local") {
            let disabledRoots = [
                "/usr/local/bin", "/usr/local/lib", "/usr/local/etc",
                "/usr/local/include", "/usr/local/share"
            ]
            if disabledRoots.contains(path) {
                return .packageManaged
            }
            return .packageContent
        }
        if inside(path, root: "/usr") {
            return .companionSystem
        }

        if let root = firstRootComponent(of: path),
           !["Applications", "Users", "Library", "System", "usr", "opt"].contains(root) {
            return .companionSystem
        }

        return .regular
    }

    private static func sharedUserPolicy(for path: String) -> FileAccessPolicy? {
        let root = "/Users/Shared"
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) {
            return .userFolderWarning
        }

        let lockedNames = ["SC Info", ".betamigrated"]
        if matchesAnyRoot(path, names: lockedNames, under: root) {
            return .systemProtected
        }
        return .userFileWarning
    }

    private static func userHomePolicy(
        for path: String,
        home: String,
        isDirectory: Bool?
    ) -> FileAccessPolicy? {
        guard insideInsensitive(path, root: home) else { return nil }
        if samePath(path, home) {
            return .selectionDisabled
        }

        let userLibrary = home + "/Library"
        if insideInsensitive(path, root: userLibrary) {
            return userLibraryPolicy(for: path, root: userLibrary, isDirectory: isDirectory)
        }

        let userName = URL(fileURLWithPath: home).lastPathComponent
        let lockedNames = [
            ".CFUserTextEncoding", ".zprofile", ".zshrc", ".config",
            ".local", ".lesshst", ".zsh_sessions", ".zsh_history",
            ".zprofile.pysave", ".swiftpm", "Pictures", userName
        ]
        if matchesAnyRoot(path, names: lockedNames, under: home) {
            return .personalProtected
        }

        let plainWrapperNames = [".Trash", "Desktop", "Downloads"]
        for name in plainWrapperNames {
            let root = home + "/" + name
            if samePath(path, root) {
                return .selectionDisabled
            }
            if insideInsensitive(path, root: root) {
                return .regular
            }
        }

        let warningSelectableNames = [
            ".vscode", ".codex", ".npm", ".go", ".m2", ".copilot",
            ".thumbnails", ".anydesk", ".cagent", ".docker",
            ".vscode-shared", ".streamlit", ".dlv", ".gitconfig",
            ".idlerc", ".mysql_history", ".psql_history"
        ]
        if matchesAnyRoot(path, names: warningSelectableNames, under: home) {
            return .userFileWarning
        }

        let documents = home + "/Documents"
        if samePath(path, documents) {
            return .userFolderWarning
        }
        if insideInsensitive(path, root: documents) {
            let warningNames = [
                "Axure", "iZotope", "A.O.M. Presets", "ChatGPT data",
                "Zoom", "appLogs.txt", "FabFilter", "Codex", "Adobe", "GitHub"
            ]
            if matchesAnyRoot(path, names: warningNames, under: documents) {
                return .userFileWarning
            }
            return .regular
        }

        let cache = home + "/.cache"
        if samePath(path, cache) {
            return .userFolderWarning
        }
        if insideInsensitive(path, root: cache + "/gstreamer-1.0") {
            return .personalProtected
        }
        if insideInsensitive(path, root: cache) {
            return .userFileWarning
        }

        let movies = home + "/Movies"
        if samePath(path, movies) {
            return .userFolderWarning
        }
        if insideInsensitive(path, root: movies) {
            let lockedNames = [
                "Медиатека iMovie.imovielibrary", "TV",
                "Motion Templates.localized", "iMovie Theater.theater"
            ]
            if matchesAnyRoot(path, names: lockedNames, under: movies) {
                return .personalProtected
            }
            return .userFileWarning
        }

        let music = home + "/Music"
        if samePath(path, music) {
            return .userFolderWarning
        }
        if insideInsensitive(path, root: music) {
            let lockedNames = ["Audio Music Apps", "Music", "GarageBand"]
            if matchesAnyRoot(path, names: lockedNames, under: music) {
                return .personalProtected
            }
            if matchesAnyRoot(path, names: ["Audified"], under: music) {
                return .userFileWarning
            }

            let logic = music + "/Logic"
            if samePath(path, logic) {
                return .userFolderWarning
            }
            if insideInsensitive(path, root: logic) {
                return .userFileWarning
            }
            return .regular
        }

        let warningContentWrappers = [".cups", "Public", "Sites", "Templates"]
        for name in warningContentWrappers {
            let root = home + "/" + name
            if samePath(path, root) {
                return name == ".cups" ? .userFolderWarning : .selectionDisabled
            }
            if insideInsensitive(path, root: root) {
                return .userFileWarning
            }
        }

        return adaptiveFallbackPolicy(for: path, root: home, scope: .userHome)
    }

    private static func userLibraryPolicy(
        for path: String,
        root: String,
        isDirectory: Bool?
    ) -> FileAccessPolicy {
        if samePath(path, root) { return .userFolderWarning }
        if let policy = userLibraryDeveloperPolicy(for: path, root: root + "/Developer") { return policy }
        if let policy = userLibraryCachesPolicy(for: path, root: root + "/Caches") { return policy }
        if let policy = userApplicationSupportPolicy(for: path, root: root + "/Application Support") { return policy }

        let lockedNames = [
            "Daemon Containers", "Biome", "Metadata", "DuetExpertCenter", "IntelligencePlatform",
            "Mail", "Mobile Documents", "Keychains", "Safari", "SafariSandboxBroker",
            "IdentityServices", "HomeKit", "Messages", "Photos", "Shortcuts", "Assistant",
            "Assistants", "Accessibility", "Weather", "AppleMediaServices", "com.apple.AppleMediaServices",
            "Finance", "FinanceBackup", "Suggestions", "Trial", "PersonalizationPortrait",
            "com.apple.aiml.instrumentation", "MediaAnalysis", "StatusKit", "com.apple.iTunesCloud",
            "FrontBoard", "com.apple.bluetooth.services.cloud", "com.apple.bluetoothuser", "Accounts",
            "Passes", "LanguageModeling", "Intents", "KeyboardServices", "Keyboard", "homeenergyd",
            "com.apple.appleaccountd", "UnifiedAssetFramework", "DoNotDisturb", "com.apple.internal.ck",
            "Contacts", "Translation", "Sharing", "ContainerManager", "GroupContainersAlias", "CoreFollowUp",
            "ResponseKit", "DataDelivery Services", "DataAccess", "LockdownMode", "Reminders",
            "SafariSafeBrowsing", "Spotlight", "Calendars", "CallServices", "CloudStorage", "DES", "GameKit",
            "News", "PrivateCloudCompute", "Staging", "studentd", "Synced Preferences", "Autosave Information",
            "Group Containers", "Preferences", "Logs", "iTunes", "org.swift.swiftpm", "FontCollections",
            "Application Scripts", "LaunchAgents", "Saved Searches", "Spelling", "ColorPickers", "Colors",
            "Compositions", "Cookies", "Input Methods", "Keyboard Layouts", "Screen Savers", "Services",
            "Saved Application State"
        ]
        if matchesAnyRoot(path, names: lockedNames, under: root) { return .personalProtected }

        let containers = root + "/Containers"
        if samePath(path, containers) { return .userFolderWarning }
        if insideInsensitive(path, root: containers) {
            let owner = relativeComponents(path, under: containers).first ?? ""
            return owner.lowercased().hasPrefix("com.apple") ? .personalProtected : .userFileWarning
        }

        let audio = root + "/Audio"
        if insideInsensitive(path, root: audio) {
            let depth = relativeComponents(path, under: audio).count
            return depth == 0 || (depth == 1 && isDirectory != false) ? .userFolderWarning : .userFileWarning
        }

        let httpStorages = root + "/HTTPStorages"
        if insideInsensitive(path, root: httpStorages) { return .personalProtected }

        for name in ["WebKit", "Sounds", "PreferencePanes", "Preference Panes", "Printers", "Internet Plug-Ins", "Favorites"] {
            let itemRoot = root + "/" + name
            if samePath(path, itemRoot) { return .userFolderWarning }
            if insideInsensitive(path, root: itemRoot) { return .userFileWarning }
        }

        let fonts = root + "/Fonts"
        if samePath(path, fonts) { return .selectionDisabled }
        if insideInsensitive(path, root: fonts) { return .regular }

        if matchesAnyRoot(path, names: ["Cableguys", "Polyverse", "DBeaverData", "Python", "NGL", "PhotoshopCrashes"], under: root) {
            return .userFileWarning
        }
        return adaptiveFallbackPolicy(for: path, root: root, scope: .userLibrary)
    }

    private static func userLibraryDeveloperPolicy(for path: String, root: String) -> FileAccessPolicy? {
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) { return .userFolderWarning }

        let xcode = root + "/Xcode"
        if insideInsensitive(path, root: xcode) {
            if samePath(path, xcode) { return .userFolderWarning }
            for name in ["DerivedData", "Code Assistant"] {
                let cleanableRoot = xcode + "/" + name
                if samePath(path, cleanableRoot) { return .userFolderWarning }
                if insideInsensitive(path, root: cleanableRoot) { return .userFileWarning }
            }
            return .personalProtected
        }

        let simulator = root + "/CoreSimulator"
        if insideInsensitive(path, root: simulator) {
            if samePath(path, simulator) { return .userFolderWarning }
            let devices = simulator + "/Devices"
            if samePath(path, devices) { return .userFolderWarning }
            if insideInsensitive(path, root: devices) { return .userFileWarning }
            return .personalProtected
        }
        return .personalProtected
    }

    private static func userLibraryCachesPolicy(for path: String, root: String) -> FileAccessPolicy? {
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) { return .userFolderWarning }

        let selectableNames = [
            "Homebrew", "Adobe", "com.adobe.Photoshop", "com.adobe.AdobeCRDaemon", "com.spotify.client",
            "hidemyname.vpn", "Codex", "com.openai.codex", "com.openai.sky.CUAService",
            "com.macpaw.CleanMyMac4", "go-build", "gopls", "goimports", "org.swift.swiftpm",
            "com.microsoft.VSCode", "com.microsoft.VSCode.ShipIt", "com.github.GitHubClient",
            "com.github.GitHubClient.ShipIt", "us.zoom.xos", "copilot", "com.crashlytics.data",
            "io.sentry", "SentryCrash", "io.branch.network.cache", "appsflyer-v1", "google-sdks-events",
            "archive_with_certs.zip", "v2_archive_with_certs_for_openvpn.zip", "archive.zip"
        ]
        if matchesAnyRoot(path, names: selectableNames, under: root) { return .userFileWarning }

        let lockedNames = [
            "GeoServices", "com.apple.geoanalyticsd", "com.apple.helpd", "com.apple.tipsd",
            "com.apple.e5rt.e5bundlecache", "com.apple.VisualIntelligenceCore", "com.apple.visualintelligenced",
            "com.apple.intelligenceflow.intelligenceflowd", "com.apple.textunderstandingd",
            "com.apple.appstoreagent", "com.apple.appstorecomponentsd", "com.apple.amsengagementd",
            "com.apple.AppleMediaServices", "com.apple.amsaccountsd", "com.apple.AMPLibraryAgent",
            "com.apple.itunescloudd", "com.apple.AMPDevicesAgent", "com.apple.dt.Xcode", "AudioUnitCache",
            "com.apple.Family-Settings.extension", "familycircled",
            "com.apple.AuthenticationServicesCore.AuthenticationServicesAgent", "com.apple.akd",
            "com.apple.FeatureAccessAgent", "com.apple.ctcategories.service", "com.apple.ap.adprivacyd",
            "GameKit", "com.apple.gamed", "com.apple.iCloudNotificationAgent", "com.apple.translationd",
            "com.apple.homed", "com.apple.HomeKit", "com.apple.Safari", "com.apple.Safari.SafeBrowsing",
            "com.apple.parsecd", "com.apple.managedappdistributionagent", "com.apple.python", "com.apple.accountsd",
            "com.apple.preferencepanes.usercache", "com.apple.duetexpertd", "com.apple.proactive.eventtracker",
            "com.apple.remindd", "com.apple.icloudwebd", "com.apple.betaenrollmentagent",
            "com.apple.siri.conversationhandlercache.plist", "com.apple.siri.bundleservicecache.plist",
            "com.apple.siri.transformationplugincache.plist", "com.apple.AssistantServices", "com.apple.sirittsd",
            "com.apple.cache_delete", "com.apple.feedbacklogger", "com.apple.nsservicescache.plist",
            "com.apple.findmy.findmylocateagent", "com.apple.sprocket.menucache", "com.apple.VideoConference",
            "com.apple.AvatarKit", "com.apple.businessservicesd", "com.apple.tiswitcher.cache", "CloudKit",
            "com.apple.bird", "com.apple.icloudmailagent", "com.apple.dataaccess.dataaccessd",
            "com.apple.nsurlsessiond", "INSTALLATION", "ssu"
        ]
        if matchesAnyRoot(path, names: lockedNames, under: root) { return .personalProtected }
        return adaptiveFallbackPolicy(for: path, root: root, scope: .userCaches)
    }

    private static func userApplicationSupportPolicy(for path: String, root: String) -> FileAccessPolicy? {
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) { return .userFolderWarning }
        if insideInsensitive(path, root: root + "/MobileSync") { return .finderManagedBackup }

        let lockedNames = [
            "com.apple.mobileAssetDesktop", "Knowledge", "AddressBook", "com.apple.wallpaper", "FileProvider",
            "CloudDocs", "iCloud", "com.apple.ProtectedCloudStorage", "CallHistoryDB", "CallHistoryTransactions",
            "FaceTime", "networkserviceproxy", "com.apple.siri.inference", "DifferentialPrivacy",
            "videosubscriptionsd", "com.apple.sbd", "Animoji", "com.apple.iTunesCloud",
            "com.apple.control-center.tips", "com.apple.ap.promotedcontentd", "com.apple.sharedfilelist",
            "com.apple.callintelligenced", "SyncServices", "com.apple.controlcenter", "ControlCenter", "Music",
            "com.apple.akd", "default.store", "default.store-shm", "default.store-wal", "com.apple.MediaPlayer",
            "com.apple.MediaPlaybackCore.PlaybackEventStreams", "com.apple.spotlight", "Spotlight", "Dock",
            "App Store", "com.apple.NewDeviceOutreach", "TV", "com.apple.windowmanager",
            "com.apple.LaunchServicesTemplateApp.dv", "com.apple.appleintelligencereporting.processing", "icdd",
            "AskPermission", "com.apple.avfoundation", "com.apple.RemoteManagementAgent", "appplaceholdersyncd",
            "com.apple.backgroundtaskmanagementagent", "com.apple.ContextStoreAgent", "com.apple.exchangesync",
            "com.apple.productdocuments", "com.apple.replayd", "com.apple.shazamd", "contactsd", "FamilySettings",
            "homeenergyd", "icloudmailagent", "identityservicesd", "IntelligenceFlow", "locationaccessstored",
            "privatecloudcomputed", "stickersd", "tipsd", "CrashReporter", "Portable_SSD", "bx", "iConf", "CEF",
            "google-heartbeat-storage", "segment", "OpenVR"
        ]
        if matchesAnyRoot(path, names: lockedNames, under: root) { return .personalProtected }
        let firstName = relativeComponents(path, under: root).first ?? ""
        if firstName.lowercased().hasPrefix("com.apple.appintents.liveentityservic") { return .personalProtected }

        for name in ["io.branch", "Logic", "iMovie", "Google"] {
            let itemRoot = root + "/" + name
            if samePath(path, itemRoot) { return .userFolderWarning }
            if insideInsensitive(path, root: itemRoot) { return .userFileWarning }
        }

        let selectableNames = [
            "Code", "zoom.us", "discord", "Adobe", "com.adobe.dunamis", "Spotify", "JetBrains", "Codex",
            "com.openai.codex", "Claude", "com.openai.chat", "FabFilter", "Waves Audio", "Waves Central",
            "iZotope", "Antares", "Plugin Alliance", "RØDE", "Docker Desktop", "GitHub Desktop", "Microsoft",
            "Blender", "com.apple.dt.Xcode", "Xcode", "Instruments", "hidemyname.vpn", "virtualenv", "go",
            "com.openai.codex.installer", "uTorrent Web", "BitTorrentHelper", "Axure", "Postgres", "MySQL",
            "PostgresLoginHelper", "PostgresMenuHelper", "CleanMyMac X", "CleanMyMac X HealthMonitor",
            "CleanMyMac X Menu", "Nitro PDF Pro", "com.gonitro.NitroPDFPro.retail", "IsolatedStorage", "OpenAI"
        ]
        if matchesAnyRoot(path, names: selectableNames, under: root) { return .userFileWarning }
        return adaptiveFallbackPolicy(for: path, root: root, scope: .userApplicationSupport)
    }

    private static func libraryPolicy(
        for path: String,
        isDirectory: Bool?
    ) -> FileAccessPolicy {
        let lockedNames = [
            "Apple", "Bluetooth", "Keychains", "Security", "OpenDirectory",
            "Preferences", "SystemExtensions", "DriverExtensions", "Extensions",
            "StagedExtensions", "StagedDriverExtensions", "KernelCollections",
            "Filesystems", "GPUBundles", "Graphics", "Updates",
            "InstallerSandboxes", "Receipts", "SystemMigration", "Sandbox",
            "User Template", "SystemProfiler", "Ruby", "Perl", "Trial",
            "OSAnalytics", "Caches", "Logs", "CoreAnalytics", "AppStore",
            "Catacomb", "Image Capture", "ColorSync", "Scripts",
            "User Pictures", "Documentation"
        ]
        if matchesAnyRoot(path, names: lockedNames, under: "/Library") {
            return .systemProtected
        }

        if let policy = applicationSupportPolicy(for: path) {
            return policy
        }
        if let policy = developerPolicy(for: path) {
            return policy
        }
        if let policy = audioPolicy(for: path, isDirectory: isDirectory) {
            return policy
        }
        if let policy = shallowDirectoryPolicy(
            for: path,
            root: "/Library/Video",
            isDirectory: isDirectory
        ) {
            return policy
        }
        if let policy = shallowDirectoryPolicy(
            for: path,
            root: "/Library/CoreMediaIO",
            isDirectory: isDirectory
        ) {
            return policy
        }

        if samePath(path, "/Library/Java") {
            return .libraryFolderWarning
        }
        if insideInsensitive(path, root: "/Library/Java") {
            return .libraryWarning
        }

        if samePath(path, "/Library/Frameworks") {
            return .libraryFolderWarning
        }
        if insideInsensitive(path, root: "/Library/Frameworks/iTunesLibrary.framework") {
            return .systemProtected
        }
        if insideInsensitive(path, root: "/Library/Frameworks") {
            return .libraryWarning
        }

        if samePath(path, "/Library/Speech") {
            return .libraryFolderWarning
        }
        if samePath(path, "/Library/Speech/Synthesizers") {
            return .libraryFolderWarning
        }
        if insideInsensitive(path, root: "/Library/Speech") {
            return .libraryWarning
        }

        let warningRoots = [
            "Components", "PrivilegedHelperTools", "LaunchDaemons",
            "LaunchAgents", "StartupItems", "Printers", "Fonts",
            "PreferencePanes", "QuickLook", "Internet Plug-Ins",
            "ScriptingAdditions", "Contextual Menu Items", "Input Methods",
            "Keyboard Layouts", "ColorPickers", "Screen Savers", "Compositions"
        ]
        for name in warningRoots {
            let root = "/Library/" + name
            if samePath(path, root) {
                return .libraryFolderWarning
            }
            if insideInsensitive(path, root: root) {
                return .libraryWarning
            }
        }

        if matchesAnyRoot(path, names: ["Tailscale", "Google"], under: "/Library") {
            return .libraryWarning
        }

        return adaptiveFallbackPolicy(for: path, root: "/Library", scope: .localLibrary)
    }

    private static func applicationSupportPolicy(for path: String) -> FileAccessPolicy? {
        let root = "/Library/Application Support"
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) {
            return .libraryFolderWarning
        }

        let lockedNames = [
            "Apple", "com.apple.TCC", "Script Editor", "BTServer",
            "com.apple.TVIdleScreen", "App Store",
            "com.apple.backgroundassets.user", "com.apple.idleassetsd",
            "livefsd", "iLifeMediaBrowser", "CrashReporter"
        ]
        if matchesAnyRoot(path, names: lockedNames, under: root) {
            return .systemProtected
        }

        let selectableNames = [
            "Logic", "GarageBand", "ProApps", "iZotope", "Adobe",
            "Red Giant", "Audified", "Waves", "Avid", "Slate Digital",
            "Valhalla DSP, LLC", "Native Instruments", "SIR Audio Tools",
            "Mozilla", "Propellerhead Software",
            "regid.1986-12.com.adobe", "Reprise"
        ]
        if matchesAnyRoot(path, names: selectableNames, under: root) {
            return .libraryWarning
        }

        return .libraryFolderWarning
    }

    private static func developerPolicy(for path: String) -> FileAccessPolicy? {
        let root = "/Library/Developer"
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) {
            return .libraryFolderWarning
        }

        let lockedRoots = [
            "DeveloperDiskImages", "CoreDevice", "PrivateFrameworks", "DeviceKit"
        ]
        if matchesAnyRoot(path, names: lockedRoots, under: root) {
            return .systemProtected
        }

        let commandLineTools = root + "/CommandLineTools"
        if samePath(path, commandLineTools) {
            return .libraryWarning
        }
        if insideInsensitive(path, root: commandLineTools) {
            return .libraryFolderWarning
        }

        let coreSimulator = root + "/CoreSimulator"
        if samePath(path, coreSimulator) {
            return .libraryFolderWarning
        }
        if insideInsensitive(path, root: coreSimulator) {
            let protectedNames = ["Profiles", "Images", "Cryptex", "Volumes"]
            if matchesAnyRoot(path, names: protectedNames, under: coreSimulator) {
                return .systemProtected
            }

            let dyld = coreSimulator + "/dyld"
            if samePath(path, dyld) {
                return .libraryFolderWarning
            }
            if insideInsensitive(path, root: dyld) {
                return .libraryWarning
            }

            let caches = coreSimulator + "/Caches"
            if insideInsensitive(path, root: caches) {
                return .libraryFolderWarning
            }
            return .libraryFolderWarning
        }

        return .libraryFolderWarning
    }

    private static func audioPolicy(
        for path: String,
        isDirectory: Bool?
    ) -> FileAccessPolicy? {
        let root = "/Library/Audio"
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) {
            return .libraryFolderWarning
        }

        let components = relativeComponents(path, under: root)
        if components.first?.caseInsensitiveCompare("Plug-Ins") == .orderedSame {
            if components.count == 1 {
                return .libraryFolderWarning
            }
            if components.count == 2 {
                if components[1].caseInsensitiveCompare("WPAPI") == .orderedSame {
                    return .libraryWarning
                }
                return isDirectory == false ? .libraryWarning : .libraryFolderWarning
            }
            return .libraryWarning
        }

        if components.count == 1 {
            return isDirectory == false ? .libraryWarning : .libraryFolderWarning
        }
        return .libraryWarning
    }

    private static func shallowDirectoryPolicy(
        for path: String,
        root: String,
        isDirectory: Bool?
    ) -> FileAccessPolicy? {
        guard insideInsensitive(path, root: root) else { return nil }
        if samePath(path, root) {
            return .libraryFolderWarning
        }

        let components = relativeComponents(path, under: root)
        if components.count == 1 {
            return isDirectory == false ? .libraryWarning : .libraryFolderWarning
        }
        return isDirectory == false ? .libraryWarning : .libraryFolderWarning
    }

    /// Exact path rules above always win. This layer classifies only objects that did not
    /// exist in the bundled knowledge base, so a future macOS update fails closed in
    /// sensitive locations without making ordinary user files look like system data.
    private enum AdaptiveScope {
        case localLibrary
        case userLibrary
        case userCaches
        case userApplicationSupport
        case userHome
    }

    private static func adaptiveFallbackPolicy(
        for path: String,
        root: String,
        scope: AdaptiveScope
    ) -> FileAccessPolicy {
        let relative = relativeComponents(path, under: root)
        let boundaryName = relative.first ?? URL(fileURLWithPath: path).lastPathComponent
        let itemName = URL(fileURLWithPath: path).lastPathComponent

        // New Apple-owned namespaces are protected automatically. Explicit exceptions
        // (for example a known Xcode cache) have already returned before this fallback.
        if looksAppleOwned(boundaryName) || looksAppleOwned(itemName) {
            switch scope {
            case .localLibrary:
                return .systemProtected
            case .userLibrary, .userCaches, .userApplicationSupport:
                return .personalProtected
            case .userHome:
                break
            }
        }

        // Libraries, system extensions and user media libraries must be managed as a
        // package. A newly introduced package therefore cannot become selectable merely
        // because KleanBytes has not seen its name yet.
        if isProtectedPackage(itemName, scope: scope) {
            return scope == .localLibrary ? .systemProtected : .personalProtected
        }

        // SQLite databases and their sidecars are one logical unit. Inside application
        // data areas we keep unknown databases locked instead of exposing individual files.
        if scope == .userApplicationSupport && isDatabaseMember(itemName) {
            return .personalProtected
        }

        switch scope {
        case .localLibrary, .userLibrary, .userCaches, .userApplicationSupport:
            return .userFolderWarning
        case .userHome:
            return .regular
        }
    }

    private static func looksAppleOwned(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized == "apple"
            || normalized == "app store"
            || normalized.hasPrefix("com.apple.")
            || normalized.hasPrefix("group.com.apple.")
    }

    private static func isProtectedPackage(_ name: String, scope: AdaptiveScope) -> Bool {
        let fileExtension = URL(fileURLWithPath: name).pathExtension.lowercased()
        let userMediaExtensions = [
            "photoslibrary", "photolibrary", "imovielibrary", "musiclibrary", "theater"
        ]
        if userMediaExtensions.contains(fileExtension) { return true }

        guard scope == .localLibrary else { return false }
        return ["kext", "framework", "systemextension", "dext"].contains(fileExtension)
    }

    private static func isDatabaseMember(_ name: String) -> Bool {
        let normalized = name.lowercased()
        let fileExtension = URL(fileURLWithPath: normalized).pathExtension
        return ["sqlite", "sqlite3", "db", "store"].contains(fileExtension)
            || normalized.hasSuffix("-wal")
            || normalized.hasSuffix("-shm")
    }

    private static func matchesAnyRoot(
        _ path: String,
        names: [String],
        under parent: String
    ) -> Bool {
        names.contains {
            insideInsensitive(path, root: parent + "/" + $0)
        }
    }

    private static func relativeComponents(_ path: String, under root: String) -> [String] {
        guard insideInsensitive(path, root: root), !samePath(path, root) else {
            return []
        }
        return String(path.dropFirst(root.count + 1))
            .split(separator: "/")
            .map(String.init)
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func insideInsensitive(_ path: String, root: String) -> Bool {
        let lowerPath = path.lowercased()
        let lowerRoot = root.lowercased()
        return lowerPath == lowerRoot || lowerPath.hasPrefix(lowerRoot + "/")
    }

    private static func firstRootComponent(of path: String) -> String? {
        path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
    }

    private static func inside(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
