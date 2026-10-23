import AppKit
import Darwin
import Foundation
import Security
import ServiceManagement

@objc(KleanBytesPrivilegedDeletionXPC)
private nonisolated protocol PrivilegedDeletionXPC {
    func delete(
        _ requestData: Data,
        authorizationData: Data,
        withReply reply: @escaping (Data?, String?) -> Void
    )
}

private nonisolated final class XPCReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didReply = false

    func resume(
        _ continuation: CheckedContinuation<Data, Error>,
        with result: Result<Data, Error>
    ) {
        lock.lock()
        guard !didReply else {
            lock.unlock()
            return
        }
        didReply = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

nonisolated enum DeletionRisk: Sendable {
    case normal
    case requiresAdministrator
    case requiresUnlockWarning
    case systemProtected(String)
}

nonisolated struct DeletionTargetAssessment: Identifiable, Sendable {
    let url: URL
    let risk: DeletionRisk
    let isUserImmutable: Bool

    var id: URL { url }
}

nonisolated struct SecureDeletionPlan: Sendable {
    let operationID: UUID
    let targets: [DeletionTargetAssessment]

    var deletableTargets: [DeletionTargetAssessment] {
        targets.filter {
            if case .systemProtected = $0.risk { return false }
            return true
        }
    }

    var protectedTargets: [DeletionTargetAssessment] {
        targets.filter {
            if case .systemProtected = $0.risk { return true }
            return false
        }
    }

    var requiresAdministrator: Bool {
        deletableTargets.contains {
            switch $0.risk {
            case .requiresAdministrator, .requiresUnlockWarning:
                true
            default:
                false
            }
        }
    }

    var requiresUnlockWarning: Bool {
        deletableTargets.contains {
            if case .requiresUnlockWarning = $0.risk { return true }
            return false
        }
    }
}

nonisolated struct SecureDeletionResult: Sendable {
    struct Failure: Sendable {
        let url: URL
        let reason: String
        let isSystemProtected: Bool
    }

    let removedURLs: [URL]
    let failures: [Failure]

    var succeeded: Bool { failures.isEmpty }
    var partiallySucceeded: Bool { !removedURLs.isEmpty && !failures.isEmpty }
}

nonisolated enum PrivilegedDeletionError: LocalizedError {
    case noTargets
    case helperUnavailable
    case authorizationDenied
    case helperFailed(String)
    case invalidHelperReply
    case helperRequiresApproval
    case helperTimedOut

    var errorDescription: String? {
        switch self {
        case .noTargets:
            "Нет объектов, которые можно удалить."
        case .helperUnavailable:
            "macOS не распознала встроенный helper KleanBytes. Переустановите актуальную сборку приложения."
        case .authorizationDenied:
            "Удаление отменено: права администратора не предоставлены."
        case .helperFailed(let message):
            "Helper не смог выполнить удаление: \(message)"
        case .invalidHelperReply:
            "Helper вернул некорректный результат."
        case .helperRequiresApproval:
            "Разрешите KleanBytes работать в фоне в Системных настройках, затем повторите удаление."
        case .helperTimedOut:
            "Helper не ответил вовремя. Перезапустите KleanBytes и повторите удаление."
        }
    }
}

actor PrivilegedDeletionService {
    private struct HelperRequest: Codable {
        struct Target: Codable {
            let path: String
            let mayUnlockUserImmutable: Bool
        }

        let operationID: UUID
        let requestingUserID: uid_t
        let targets: [Target]
    }

    private struct HelperReply: Codable {
        struct Failure: Codable {
            let path: String
            let reason: String
            let isSystemProtected: Bool
        }

        let operationID: UUID
        let removedPaths: [String]
        let failures: [Failure]
    }

    private let fileManager = FileManager.default

    func makePlan(for urls: [URL], warningURLs: Set<URL> = []) -> SecureDeletionPlan {
        let warningPaths = Set(warningURLs.map { $0.standardizedFileURL.path })
        let targets = topLevelURLs(from: urls).map { url in
            let assessment = assess(url)
            guard warningPaths.contains(url.standardizedFileURL.path) else { return assessment }
            if case .systemProtected = assessment.risk { return assessment }
            return DeletionTargetAssessment(
                url: assessment.url,
                risk: .requiresUnlockWarning,
                isUserImmutable: assessment.isUserImmutable
            )
        }
        return SecureDeletionPlan(operationID: UUID(), targets: targets)
    }

    func delete(_ plan: SecureDeletionPlan) async throws -> SecureDeletionResult {
        let permitted = plan.deletableTargets
        guard !permitted.isEmpty else {
            return SecureDeletionResult(
                removedURLs: [],
                failures: plan.protectedTargets.map {
                    .init(url: $0.url, reason: protectionReason(for: $0), isSystemProtected: true)
                }
            )
        }

        var removed: [URL] = []
        var failures = plan.protectedTargets.map {
            SecureDeletionResult.Failure(
                url: $0.url,
                reason: protectionReason(for: $0),
                isSystemProtected: true
            )
        }

        var privileged = permitted.filter { assessment in
            switch assessment.risk {
            case .requiresAdministrator, .requiresUnlockWarning:
                true
            default:
                false
            }
        }
        let ordinary = permitted.filter { assessment in
            switch assessment.risk {
            case .normal:
                true
            default:
                false
            }
        }

        for target in ordinary {
            do {
                let reassessed = assess(target.url)
                switch reassessed.risk {
                case .normal:
                    try fileManager.removeItem(at: target.url)
                    removed.append(target.url)
                case .requiresAdministrator, .requiresUnlockWarning:
                    privileged.append(reassessed)
                case .systemProtected:
                    failures.append(
                        .init(
                            url: target.url,
                            reason: protectionReason(for: reassessed),
                            isSystemProtected: true
                        )
                    )
                }
            } catch {
                // FileManager can wrap a permissions failure from a child of a
                // directory in a generic Cocoa write error. This is common for
                // installer-owned directory applications such as XAMPP. If the
                // top-level target still exists, let the root helper retry it;
                // the helper independently validates every requested path.
                if shouldRetryWithAdministrator(target.url, after: error) {
                    privileged.append(
                        .init(
                            url: target.url,
                            risk: .requiresAdministrator,
                            isUserImmutable: target.isUserImmutable
                        )
                    )
                } else {
                    failures.append(
                        .init(
                            url: target.url,
                            reason: error.localizedDescription,
                            isSystemProtected: false
                        )
                    )
                }
            }
        }

        if !privileged.isEmpty {
            let authorization = try requestFreshAdministratorAuthorization()
            defer { AuthorizationFree(authorization, [.destroyRights]) }
            let helperResult: SecureDeletionResult
            do {
                helperResult = try await runHelper(
                    operationID: plan.operationID,
                    targets: privileged,
                    authorization: authorization
                )
            } catch PrivilegedDeletionError.helperTimedOut {
                try repairHelperRegistration()
                helperResult = try await runHelper(
                    operationID: plan.operationID,
                    targets: privileged,
                    authorization: authorization
                )
            }
            removed.append(contentsOf: helperResult.removedURLs)
            failures.append(contentsOf: helperResult.failures)
        }

        return SecureDeletionResult(removedURLs: removed, failures: failures)
    }

    private func shouldRetryWithAdministrator(_ url: URL, after error: Error) -> Bool {
        if isPermissionError(error) { return true }

        let path = url.standardizedFileURL.path
        let isEligibleManagedLocation = [
            "/Applications/", "/Library/", "/Users/", "/Volumes/", "/usr/local/"
        ].contains(where: path.hasPrefix)
        return isEligibleManagedLocation && fileManager.fileExists(atPath: path)
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileWriteNoPermission.rawValue
                || nsError.code == CocoaError.fileWriteVolumeReadOnly.rawValue {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionError(underlying)
        }
        return false
    }

    private func assess(_ inputURL: URL) -> DeletionTargetAssessment {
        let url = inputURL.standardizedFileURL
        if let reason = protectedReason(for: url) {
            return .init(url: url, risk: .systemProtected(reason), isUserImmutable: false)
        }

        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            return .init(url: url, risk: .normal, isUserImmutable: false)
        }

        if info.st_flags & UInt32(SF_IMMUTABLE | SF_RESTRICTED) != 0 {
            return .init(
                url: url,
                risk: .systemProtected("Объект защищён системным immutable-флагом."),
                isUserImmutable: false
            )
        }

        let userImmutable = info.st_flags & UInt32(UF_IMMUTABLE) != 0
        if userImmutable {
            return .init(url: url, risk: .requiresUnlockWarning, isUserImmutable: true)
        }

        let parent = url.deletingLastPathComponent()
        let needsAdministrator = !fileManager.isWritableFile(atPath: parent.path)
            || !fileManager.isDeletableFile(atPath: url.path)
        return .init(
            url: url,
            risk: needsAdministrator ? .requiresAdministrator : .normal,
            isUserImmutable: false
        )
    }

    private func protectedReason(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let app = Bundle.main.bundleURL.standardizedFileURL.path
        let exactRoots = [
            "/", "/System", "/bin", "/sbin", "/usr", "/private", "/etc", "/var",
            "/dev", "/cores", "/Library", "/Applications", "/Users", "/Volumes", home
        ]
        if exactRoots.contains(path) {
            return "Корневые системные и пользовательские каталоги защищены."
        }
        if path == app || app.hasPrefix(path + "/") {
            return "KleanBytes не может удалить собственный пакет."
        }

        let blockedTrees = [
            "/System", "/bin", "/sbin", "/private", "/etc", "/var", "/dev", "/cores",
            "/Library/Apple", "/Library/SystemExtensions", "/Library/DriverExtensions",
            "/Library/Extensions", "/Library/KernelCollections", "/Library/Keychains",
            "/Library/Security", "/Library/OpenDirectory"
        ]
        if blockedTrees.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return "Объект относится к защищённой части macOS."
        }
        if (path == "/usr" || path.hasPrefix("/usr/"))
            && !(path == "/usr/local" || path.hasPrefix("/usr/local/")) {
            return "Системная область /usr защищена."
        }

        let permittedRoots = ["/Applications/", "/Library/", "/Users/", "/Volumes/", "/usr/local/"]
        guard permittedRoots.contains(where: path.hasPrefix) else {
            return "Путь находится за пределами областей, разрешённых для очистки."
        }

        var info = stat()
        if lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            if resolved != path, protectedReason(for: URL(fileURLWithPath: resolved)) != nil {
                return "Путь ведёт в защищённую системную область."
            }
        }
        return nil
    }

    private func protectionReason(for assessment: DeletionTargetAssessment) -> String {
        if case .systemProtected(let reason) = assessment.risk { return reason }
        return "Объект защищён."
    }

    private func requestFreshAdministratorAuthorization() throws -> AuthorizationRef {
        var authorization: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw PrivilegedDeletionError.authorizationDenied
        }

        status = "system.privilege.admin".withCString { rightName in
            var right = AuthorizationItem(
                name: rightName,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &right) { rightPointer in
                var rights = AuthorizationRights(count: 1, items: rightPointer)
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil
                )
            }
        }
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(authorization, [.destroyRights])
            throw PrivilegedDeletionError.authorizationDenied
        }
        return authorization
    }

    private func runHelper(
        operationID: UUID,
        targets: [DeletionTargetAssessment],
        authorization: AuthorizationRef
    ) async throws -> SecureDeletionResult {
        let request = HelperRequest(
            operationID: operationID,
            requestingUserID: getuid(),
            targets: targets.map {
                .init(path: $0.url.path, mayUnlockUserImmutable: $0.isUserImmutable)
            }
        )
        try ensureHelperIsRegistered()
        let requestData = try JSONEncoder().encode(request)
        var externalForm = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(authorization, &externalForm) == errAuthorizationSuccess else {
            throw PrivilegedDeletionError.authorizationDenied
        }
        let authorizationData = withUnsafeBytes(of: &externalForm) { Data($0) }
        let replyData = try await sendToHelper(
            requestData: requestData,
            authorizationData: authorizationData
        )
        guard let reply = try? JSONDecoder().decode(HelperReply.self, from: replyData),
              reply.operationID == operationID else {
            throw PrivilegedDeletionError.invalidHelperReply
        }
        return SecureDeletionResult(
            removedURLs: reply.removedPaths.map { URL(fileURLWithPath: $0) },
            failures: reply.failures.map {
                .init(
                    url: URL(fileURLWithPath: $0.path),
                    reason: $0.reason,
                    isSystemProtected: $0.isSystemProtected
                )
            }
        )
    }

    private func ensureHelperIsRegistered() throws {
        let service = SMAppService.daemon(plistName: "com.alllyxer.KleanBytes.PrivilegedHelper.plist")
        switch service.status {
        case .enabled:
            return
        case .notRegistered, .notFound:
            // For a daemon the system has never encountered before, macOS can
            // report .notFound until the first registration attempt. It does
            // not necessarily mean that the embedded plist or executable is
            // missing, so registration must still be attempted here.
            do {
                try service.register()
            } catch {
                // A launch daemon may be registered only after the user allows
                // it in Login Items. Surface that required action instead of a
                // raw ServiceManagement error.
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    throw PrivilegedDeletionError.helperRequiresApproval
                }
                throw error
            }
            guard service.status == .enabled else {
                SMAppService.openSystemSettingsLoginItems()
                throw PrivilegedDeletionError.helperRequiresApproval
            }
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            throw PrivilegedDeletionError.helperRequiresApproval
        @unknown default:
            throw PrivilegedDeletionError.helperUnavailable
        }
    }

    private func repairHelperRegistration() throws {
        let service = SMAppService.daemon(plistName: "com.alllyxer.KleanBytes.PrivilegedHelper.plist")
        if service.status != .notRegistered && service.status != .notFound {
            try service.unregister()
        }

        do {
            try service.register()
        } catch {
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                throw PrivilegedDeletionError.helperRequiresApproval
            }
            throw error
        }
        guard service.status == .enabled else {
            SMAppService.openSystemSettingsLoginItems()
            throw PrivilegedDeletionError.helperRequiresApproval
        }
    }

    private func sendToHelper(requestData: Data, authorizationData: Data) async throws -> Data {
        let connection = NSXPCConnection(
            machServiceName: "com.alllyxer.KleanBytes.PrivilegedHelper",
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedDeletionXPC.self)
        connection.setCodeSigningRequirement(
            #"identifier "com.alllyxer.KleanBytes.PrivilegedHelper" and anchor apple generic and certificate leaf[subject.OU] = "YOUR_TEAM_ID""#
        )
        connection.resume()
        defer { connection.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let gate = XPCReplyGate()
            Task {
                try? await Task.sleep(for: .seconds(15))
                gate.resume(continuation, with: .failure(PrivilegedDeletionError.helperTimedOut))
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                gate.resume(
                    continuation,
                    with: .failure(PrivilegedDeletionError.helperFailed(error.localizedDescription))
                )
            }
            guard let helper = proxy as? PrivilegedDeletionXPC else {
                gate.resume(continuation, with: .failure(PrivilegedDeletionError.helperUnavailable))
                return
            }
            helper.delete(requestData, authorizationData: authorizationData) { data, message in
                if let data {
                    gate.resume(continuation, with: .success(data))
                } else {
                    gate.resume(
                        continuation,
                        with: .failure(
                            PrivilegedDeletionError.helperFailed(message ?? "Нет ответа.")
                        )
                    )
                }
            }
        }
    }

    private func topLevelURLs(from urls: [URL]) -> [URL] {
        let unique = Dictionary(grouping: urls.map(\.standardizedFileURL), by: \.path)
            .compactMap { $0.value.first }
            .sorted { $0.path.count < $1.path.count }
        var accepted: [URL] = []
        for url in unique where !accepted.contains(where: { url.path.hasPrefix($0.path + "/") }) {
            accepted.append(url)
        }
        return accepted
    }
}
