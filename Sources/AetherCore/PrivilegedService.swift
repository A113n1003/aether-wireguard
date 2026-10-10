import Foundation
import Security
import Darwin

@objc public protocol AetherPrivilegedService {
    func ping(withReply reply: @escaping (String) -> Void)
    func start(profileID: String, sessionID: String, configurationPath: String, withReply reply: @escaping (String?, String?) -> Void)
    func stop(sessionID: String, withReply reply: @escaping (String?) -> Void)
}

public enum PrivilegedServiceLocation {
    public static let name = "io.aether.wireguard.service"
    public static let directory = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/io.aether.wireguard", isDirectory: true)
    public static let executable = directory.appendingPathComponent("AetherService")
    public static let bridge = directory.appendingPathComponent("AetherBridge")
    public static let tools = directory.appendingPathComponent("Tools/bin", isDirectory: true)
}

public struct InstalledServicePolicy: Codable, Sendable {
    public let allowedUID: UInt32
    public let clientRequirement: String
}

public enum ServiceIdentity {
    public static func requirement(hash: Data, identifier: String) throws -> String {
        guard hash.count == 20, ["io.aether.wireguard", PrivilegedServiceLocation.name].contains(identifier) else { throw EngineError.operationFailed }
        return "identifier \"\(identifier)\" and cdhash H\"\(hash.map { String(format: "%02x", $0) }.joined())\""
    }

    public static func requirement(for url: URL, identifier: String) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess else { throw EngineError.operationFailed }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let info = information as? [String: Any],
              info[kSecCodeInfoIdentifier as String] as? String == identifier,
              let flags = info[kSecCodeInfoFlags as String] as? NSNumber, flags.uint32Value & 0x10000 != 0,
              let hash = info[kSecCodeInfoUnique as String] as? Data else { throw EngineError.operationFailed }
        return try requirement(hash: hash, identifier: identifier)
    }

    public static func checkRootOwnership(_ url: URL, directory: Bool = false) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == 0, info.st_mode & 0o022 == 0,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG), directory || info.st_nlink == 1 else { throw EngineError.operationFailed }
        // POSIX mode bits alone do not exclude writable inherited macOS ACLs.
        errno = 0
        if let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?
            guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw EngineError.operationFailed }
        } else if errno != ENOENT { throw EngineError.operationFailed }
    }

    public static func installedRequirement(for app: URL, uid: uid_t) throws -> String {
        for path in ["/Library", "/Library/PrivilegedHelperTools", PrivilegedServiceLocation.directory.path] {
            try checkRootOwnership(URL(fileURLWithPath: path), directory: true)
        }
        let policyURL = PrivilegedServiceLocation.directory.appendingPathComponent("policy.json")
        try checkRootOwnership(policyURL)
        try checkRootOwnership(PrivilegedServiceLocation.executable)
        let data = try Data(contentsOf: policyURL)
        guard data.count < 4096 else { throw EngineError.operationFailed }
        let policy = try JSONDecoder().decode(InstalledServicePolicy.self, from: data)
        let client = try requirement(for: app, identifier: "io.aether.wireguard")
        guard policy.allowedUID == uid, policy.clientRequirement == client else { throw EngineError.operationFailed }
        return try requirement(for: PrivilegedServiceLocation.executable, identifier: PrivilegedServiceLocation.name)
    }
}

/// One reply gate handles reply/error races without resuming an async operation twice.
private final class ServiceReply<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Value, Error>) {
        lock.lock(); let saved = continuation; continuation = nil; lock.unlock()
        saved?.resume(with: result)
    }
}

public enum PrivilegedServiceClient {
    public static func perform(_ action: String, sessionID: UUID?, profileID: UUID? = nil, configurationPath: String? = nil) async throws -> String {
        let requirement: String
        do { requirement = try ServiceIdentity.installedRequirement(for: Bundle.main.bundleURL, uid: getuid()) }
        catch { throw EngineError.unavailable("连接服务尚未设置或版本已更新，请先设置连接服务。") }
        let connection = NSXPCConnection(machServiceName: PrivilegedServiceLocation.name, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: AetherPrivilegedService.self)
        defer { connection.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let reply = ServiceReply<String>(continuation)
            connection.interruptionHandler = { reply.finish(.failure(EngineError.operationFailed)) }
            connection.invalidationHandler = { reply.finish(.failure(EngineError.operationFailed)) }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in reply.finish(.failure(EngineError.operationFailed)) }) as? AetherPrivilegedService else {
                reply.finish(.failure(EngineError.operationFailed)); return
            }
            switch action {
            case "ping": proxy.ping { version in
                reply.finish(version == "1" ? .success(version) : .failure(EngineError.operationFailed))
            }
            case "start":
                guard let sessionID, let profileID, let configurationPath else { reply.finish(.failure(EngineError.invalidSession)); return }
                proxy.start(profileID: profileID.uuidString, sessionID: sessionID.uuidString, configurationPath: configurationPath) { output, error in
                    guard error == nil, let output, output.utf8.count <= 65536 else { reply.finish(.failure(EngineError.operationFailed)); return }
                    reply.finish(.success(output))
                }
            case "stop":
                guard let sessionID else { reply.finish(.failure(EngineError.invalidSession)); return }
                proxy.stop(sessionID: sessionID.uuidString) { error in reply.finish(error == nil ? .success("") : .failure(EngineError.operationFailed)) }
            default: reply.finish(.failure(EngineError.operationFailed))
            }
        }
    }
}
