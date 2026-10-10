import Foundation
import Darwin
import AetherCore
import CryptoKit
import Security

private enum ServiceFailure: Error { case rejected, failed }

private struct ToolManifest: Decodable {
    let schemaVersion: Int
    let files: [String: String]

    static func verify(_ root: String) throws {
        try Policy.verify(root, directory: true)
        try Policy.verify(root + "/bin", directory: true)
        try Policy.verify(root + "/lib", directory: true)
        try Policy.verify(root + "/tools-manifest.json", directory: false)
        let manifestURL = URL(fileURLWithPath: root + "/tools-manifest.json")
        let data = try Data(contentsOf: manifestURL)
        guard data.count <= 65_536 else { throw ServiceFailure.rejected }
        let manifest = try JSONDecoder().decode(ToolManifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.files.count >= 4, manifest.files.count <= 64,
              ["bin/bash", "bin/wg", "bin/wg-quick", "bin/wireguard-go"].allSatisfy({ manifest.files[$0] != nil }) else { throw ServiceFailure.rejected }
        var actual = Set<String>()
        for directory in ["bin", "lib"] {
            for name in try FileManager.default.contentsOfDirectory(atPath: root + "/" + directory) {
                let relative = directory + "/" + name
                guard name.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
                      let expected = manifest.files[relative],
                      expected.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { throw ServiceFailure.rejected }
                let path = root + "/" + relative
                try Policy.verify(path, directory: false)
                let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
                guard descriptor >= 0 else { throw ServiceFailure.rejected }
                defer { close(descriptor) }
                var info = stat()
                guard fstat(descriptor, &info) == 0, info.st_uid == 0, info.st_nlink == 1,
                      info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0,
                      info.st_size > 0, info.st_size <= 100_000_000 else { throw ServiceFailure.rejected }
                let file = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readToEnd() ?? Data()
                let hash = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
                guard hash == expected else { throw ServiceFailure.rejected }
                actual.insert(relative)
            }
        }
        guard actual == Set(manifest.files.keys) else { throw ServiceFailure.rejected }
        let topLevel = Set(try FileManager.default.contentsOfDirectory(atPath: root))
        guard topLevel == ["bin", "lib", "tools-manifest.json"] else { throw ServiceFailure.rejected }
    }
}

private struct Policy: Decodable {
    let allowedUID: uid_t
    let clientRequirement: String

    static let installation = "/Library/PrivilegedHelperTools/io.aether.wireguard"

    static func load(from installation: String = installation) throws -> Policy {
        guard getuid() == 0 else { throw ServiceFailure.rejected }
        let root = URL(fileURLWithPath: installation, isDirectory: true)
        guard installation.hasPrefix("/"), root.standardizedFileURL.path == installation else { throw ServiceFailure.rejected }
        var ancestor = root
        while true {
            try verify(ancestor.path, directory: true)
            if ancestor.path == "/" { break }
            ancestor.deleteLastPathComponent()
        }
        try verify(installation + "/AetherService", directory: false)
        try verify(installation + "/AetherBridge", directory: false)
        try verifySignature(installation + "/AetherService", identifier: "io.aether.wireguard.service")
        try verifySignature(installation + "/AetherBridge", identifier: nil)
        try verify(installation + "/Tools", directory: true)
        try ToolManifest.verify(installation + "/Tools")
        try verify(installation + "/policy.json", directory: false)
        let descriptor = open(installation + "/policy.json", O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ServiceFailure.rejected }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0,
              info.st_nlink == 1, info.st_size > 0, info.st_size <= 4096 else { throw ServiceFailure.rejected }
        let data = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readToEnd() ?? Data()
        let policy = try JSONDecoder().decode(Policy.self, from: data)
        guard policy.allowedUID >= 501,
              policy.clientRequirement.range(of: #"^identifier "io\.aether\.wireguard" and cdhash H"[0-9a-f]{40}"$"#, options: .regularExpression) != nil else { throw ServiceFailure.rejected }
        return policy
    }

    static func verifySignature(_ path: String, identifier: String?) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess else { throw ServiceFailure.rejected }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              identifier == nil || info[kSecCodeInfoIdentifier as String] as? String == identifier,
              let flags = info[kSecCodeInfoFlags as String] as? NSNumber, flags.uint32Value & 0x10000 != 0 else { throw ServiceFailure.rejected }
        // Privileged executables have no reason to permit debugging or injection.
        if let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any], !entitlements.isEmpty {
            throw ServiceFailure.rejected
        }
    }

    static func verify(_ path: String, directory: Bool) throws {
        try ServiceIdentity.checkRootOwnership(URL(fileURLWithPath: path), directory: directory)
    }
}

private final class Endpoint: NSObject, AetherPrivilegedService {
    private let uid: uid_t
    private let operations: DispatchQueue
    private static let gate = NSLock()
    private static var pending = 0

    init(uid: uid_t, operations: DispatchQueue) {
        self.uid = uid
        self.operations = operations
    }

    func ping(withReply reply: @escaping (String) -> Void) { reply("1") }

    func start(profileID: String, sessionID: String, configurationPath: String,
               withReply reply: @escaping (String?, String?) -> Void) {
        guard let profile = UUID(uuidString: profileID), let session = UUID(uuidString: sessionID),
              configurationPath.hasPrefix("/"), configurationPath.utf8.count <= 4096,
              !configurationPath.contains("\0"), validConfigurationPath(configurationPath, session: session), beginOperation() else {
            reply(nil, "请求未通过验证。"); return
        }
        operations.async {
            defer { self.endOperation() }
            do {
                let result = try self.run(["start", "--uid", String(self.uid), "--id", session.uuidString,
                                           "--profile", profile.uuidString, "--config", configurationPath])
                guard let data = result.data(using: .utf8),
                      let record = try? JSONDecoder().decode(TunnelSession.self, from: data),
                      record.id == session, record.profileID == profile,
                      EngineUtilities.valid(record) else { throw ServiceFailure.failed }
                reply(result, nil)
            } catch { reply(nil, "无法建立隧道，请检查配置与连接状态。") }
        }
    }

    func stop(sessionID: String, withReply reply: @escaping (String?) -> Void) {
        guard let session = UUID(uuidString: sessionID), beginOperation() else {
            reply("请求未通过验证。"); return
        }
        operations.async {
            defer { self.endOperation() }
            do {
                _ = try self.run(["stop", "--uid", String(self.uid), "--id", session.uuidString])
                reply(nil)
            } catch { reply("无法断开隧道，请检查连接状态后重试。") }
        }
    }

    // A client cannot create an unbounded backlog of privileged operations.
    private func beginOperation() -> Bool {
        Self.gate.lock(); defer { Self.gate.unlock() }
        guard Self.pending == 0 else { return false }
        Self.pending = 1; return true
    }
    private func endOperation() {
        Self.gate.lock(); Self.pending = 0; Self.gate.unlock()
    }

    private func validConfigurationPath(_ path: String, session: UUID) -> Bool {
        guard let account = getpwuid(uid), let home = account.pointee.pw_dir else { return false }
        let expected = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Aether/runtime", isDirectory: true)
            .appendingPathComponent(session.uuidString + ".conf").path
        return path == expected
    }

    private func run(_ arguments: [String]) throws -> String {
        let bridge = Policy.installation + "/AetherBridge"
        try Policy.verify(bridge, directory: false)
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: bridge)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "WG_HIDE_KEYS": "always"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Preserve Bridge's rollback and session registration: a UI timeout must
        // never kill it midway through a network mutation.
        var data = Data()
        var oversized = false
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
            if !oversized && data.count + chunk.count <= 65_536 { data.append(chunk) }
            else { oversized = true; data.removeAll(keepingCapacity: false) }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, !oversized else { throw ServiceFailure.failed }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let policy: Policy
    let operations = DispatchQueue(label: "io.aether.wireguard.service.lifecycle")
    init(policy: Policy) { self.policy = policy }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == policy.allowedUID else { return false }
        // The OS validates the actual sending process before delivering any RPC.
        connection.setCodeSigningRequirement(policy.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: AetherPrivilegedService.self)
        connection.exportedObject = Endpoint(uid: connection.effectiveUserIdentifier, operations: operations)
        connection.resume()
        return true
    }
}

do {
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--verify-installation" {
        _ = try Policy.load(from: CommandLine.arguments[2])
        exit(0)
    }
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--verify-tools" {
        guard getuid() == 0 else { throw ServiceFailure.rejected }
        try ToolManifest.verify(CommandLine.arguments[2])
        exit(0)
    }
    guard CommandLine.arguments.count == 1 else { throw ServiceFailure.rejected }
    let policy = try Policy.load()
    let delegate = ListenerDelegate(policy: policy)
    let listener = NSXPCListener(machServiceName: "io.aether.wireguard.service")
    listener.delegate = delegate
    listener.setConnectionCodeSigningRequirement(policy.clientRequirement)
    listener.resume()
    withExtendedLifetime((listener, delegate)) { RunLoop.current.run() }
} catch {
    // Do not expose paths or privileged command output to launchd logs.
    fputs("Aether service configuration rejected.\n", stderr)
    exit(1)
}
