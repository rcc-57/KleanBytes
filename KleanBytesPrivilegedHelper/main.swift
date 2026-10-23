import Darwin
import Foundation
import Security

@objc(KleanBytesPrivilegedDeletionXPC)
private nonisolated protocol PrivilegedDeletionXPC {
    func delete(
        _ requestData: Data,
        authorizationData: Data,
        withReply reply: @escaping (Data?, String?) -> Void
    )
}

private struct DeleteRequest: Codable {
    struct Target: Codable {
        let path: String
        let mayUnlockUserImmutable: Bool
    }

    let operationID: UUID
    let requestingUserID: uid_t
    let targets: [Target]
}

private struct DeleteReply: Codable {
    struct Failure: Codable {
        let path: String
        let reason: String
        let isSystemProtected: Bool
    }

    let operationID: UUID
    var removedPaths: [String]
    var failures: [Failure]
}

private enum HelperError: LocalizedError {
    case invalidRequest
    case unauthorized
    case protectedPath(String)
    case systemImmutable
    case userImmutable

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Некорректный запрос helper."
        case .unauthorized:
            "Операция не получила одноразовое разрешение администратора."
        case .protectedPath(let reason):
            reason
        case .systemImmutable:
            "Объект защищён системным immutable-флагом."
        case .userImmutable:
            "Объект заблокирован пользователем."
        }
    }
}

private struct SafetyValidator {
    func validate(_ rawPath: String, requestingUserID: uid_t) throws -> String {
        guard rawPath.hasPrefix("/"), !rawPath.contains("\0") else {
            throw HelperError.protectedPath("Некорректный путь.")
        }

        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        let path = url.path
        guard URL(fileURLWithPath: rawPath).standardizedFileURL.path == path else {
            throw HelperError.protectedPath("Путь изменился после подтверждения.")
        }

        let criticalRoots = [
            "/", "/System", "/bin", "/sbin", "/usr", "/private", "/etc", "/var",
            "/dev", "/cores", "/Library", "/Applications", "/Users", "/Volumes"
        ]
        if criticalRoots.contains(path) {
            throw HelperError.protectedPath("Системный корневой каталог удалять запрещено.")
        }

        let blockedTrees = [
            "/System", "/bin", "/sbin", "/private", "/etc", "/var", "/dev", "/cores",
            "/Library/Apple", "/Library/SystemExtensions", "/Library/DriverExtensions",
            "/Library/Extensions", "/Library/KernelCollections", "/Library/Keychains",
            "/Library/Security", "/Library/OpenDirectory"
        ]
        if blockedTrees.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            throw HelperError.protectedPath("Объект относится к защищённой части macOS.")
        }
        if (path == "/usr" || path.hasPrefix("/usr/"))
            && !(path == "/usr/local" || path.hasPrefix("/usr/local/")) {
            throw HelperError.protectedPath("Системная область /usr защищена.")
        }

        guard path.hasPrefix("/Applications/")
                || path.hasPrefix("/Library/")
                || path.hasPrefix("/Users/")
                || path.hasPrefix("/Volumes/")
                || path.hasPrefix("/usr/local/") else {
            throw HelperError.protectedPath(
                "Удаление за пределами разрешённых пользовательских областей запрещено."
            )
        }

        let homePath = homeDirectory(for: requestingUserID)
        if path == homePath {
            throw HelperError.protectedPath("Домашний каталог пользователя защищён.")
        }

        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { return path }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if info.st_flags & UInt32(SF_IMMUTABLE | SF_RESTRICTED) != 0 {
            throw HelperError.systemImmutable
        }

        // Resolve only the parent so a selected symbolic link is removed as a link.
        let parent = url.deletingLastPathComponent().path
        guard let resolvedParent = realpath(parent, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(resolvedParent) }
        let resolvedPath = URL(fileURLWithPath: String(cString: resolvedParent))
            .appendingPathComponent(url.lastPathComponent)
            .standardizedFileURL.path
        if resolvedPath != path {
            _ = try validate(resolvedPath, requestingUserID: requestingUserID)
        }
        return path
    }

    private func homeDirectory(for userID: uid_t) -> String {
        guard let record = getpwuid(userID), let directory = record.pointee.pw_dir else {
            return "/Users"
        }
        return String(cString: directory)
    }
}

private final class DeletionEndpoint: NSObject, PrivilegedDeletionXPC {
    func delete(
        _ requestData: Data,
        authorizationData: Data,
        withReply reply: @escaping (Data?, String?) -> Void
    ) {
        do {
            let authorization = try validatedAuthorization(from: authorizationData)
            defer { AuthorizationFree(authorization, [.destroyRights]) }
            let request = try JSONDecoder().decode(DeleteRequest.self, from: requestData)
            guard !request.targets.isEmpty else { throw HelperError.invalidRequest }
            let result = perform(request)
            reply(try JSONEncoder().encode(result), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    private func validatedAuthorization(from data: Data) throws -> AuthorizationRef {
        guard data.count == MemoryLayout<AuthorizationExternalForm>.size else {
            throw HelperError.unauthorized
        }
        var externalForm = AuthorizationExternalForm()
        _ = withUnsafeMutableBytes(of: &externalForm) { data.copyBytes(to: $0) }
        var authorization: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&externalForm, &authorization) == errAuthorizationSuccess,
              let authorization else {
            throw HelperError.unauthorized
        }

        let status = "system.privilege.admin".withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(authorization, &rights, nil, [.extendRights], nil)
            }
        }
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(authorization, [.destroyRights])
            throw HelperError.unauthorized
        }
        return authorization
    }

    private func perform(_ request: DeleteRequest) -> DeleteReply {
        let validator = SafetyValidator()
        let fileManager = FileManager.default
        var result = DeleteReply(operationID: request.operationID, removedPaths: [], failures: [])
        for target in request.targets {
            do {
                let path = try validator.validate(target.path, requestingUserID: request.requestingUserID)
                if !fileManager.fileExists(atPath: path) {
                    result.removedPaths.append(path)
                    continue
                }

                var info = stat()
                guard lstat(path, &info) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                if info.st_flags & UInt32(UF_IMMUTABLE) != 0 {
                    guard target.mayUnlockUserImmutable else { throw HelperError.userImmutable }
                    guard chflags(path, info.st_flags & ~UInt32(UF_IMMUTABLE)) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
                    }
                }

                try fileManager.removeItem(atPath: path)
                result.removedPaths.append(path)
            } catch {
                result.failures.append(
                    .init(
                        path: target.path,
                        reason: error.localizedDescription,
                        isSystemProtected: error is HelperError
                    )
                )
            }
        }
        return result
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: PrivilegedDeletionXPC.self)
        connection.exportedObject = DeletionEndpoint()
        connection.setCodeSigningRequirement(
            #"identifier "com.alllyxer.KleanBytes" and anchor apple generic and certificate leaf[subject.OU] = "YOUR_TEAM_ID""#
        )
        connection.resume()
        return true
    }
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener(machServiceName: "com.alllyxer.KleanBytes.PrivilegedHelper")
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
