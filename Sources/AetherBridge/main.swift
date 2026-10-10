import Foundation
import Darwin
import AetherCore

enum BridgeFailure: Error { case rejected, failed }
struct BridgeRecord: Codable {
    let uid: uid_t
    let session: TunnelSession
}

/// This executable accepts only lifecycle actions for an app-owned session.
/// It never accepts shell commands or config hooks and never prints tool stderr.
struct Bridge {
    static let toolEnvironment = ["PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "WG_HIDE_KEYS": "always"]
    let action: String
    let uid: uid_t
    let id: UUID
    let options: [String: String]
    var root: URL { EngineUtilities.runtimeDirectory(uid: uid) }
    var directory: URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    var recordURL: URL { directory.appendingPathComponent("session.json") }
    var configurationURL: URL { directory.appendingPathComponent(EngineUtilities.logicalName(for: id) + ".conf") }
    var activeURL: URL { root.appendingPathComponent("active.json") }

    init(arguments: [String]) throws {
        guard getuid() == 0, let action = arguments.first, ["start", "stop", "monitor"].contains(action), arguments.count % 2 == 1 else { throw BridgeFailure.rejected }
        var values: [String: String] = [:]
        for index in stride(from: 1, to: arguments.count, by: 2) {
            let key = arguments[index]
            guard ["--uid", "--id", "--config", "--profile"].contains(key), values[key] == nil else { throw BridgeFailure.rejected }
            values[key] = arguments[index + 1]
        }
        guard let uidText = values["--uid"], let uid = uid_t(uidText), uid >= 501, let idText = values["--id"], let id = UUID(uuidString: idText) else { throw BridgeFailure.rejected }
        if action == "start" {
            guard values.count == 4, values["--config"] != nil, let profile = values["--profile"], UUID(uuidString: profile) != nil else { throw BridgeFailure.rejected }
        } else { guard values.count == 2 else { throw BridgeFailure.rejected } }
        self.action = action; self.uid = uid; self.id = id; self.options = values
    }

    func execute() throws {
        switch action {
        case "start": try start()
        case "stop": try stop()
        case "monitor": try monitor()
        default: throw BridgeFailure.rejected
        }
    }
    func start() throws {
        try ensureDirectory(root, create: true)
        let lock = try acquireLock()
        defer { flock(lock, LOCK_UN); close(lock) }
        if FileManager.default.fileExists(atPath: activeURL.path) {
            let active: BridgeRecord = try readRootJSON(activeURL)
            guard active.uid == uid, EngineUtilities.valid(active.session) else { throw BridgeFailure.rejected }
            if (try? readInterfaceName(for: active.session.id)) == active.session.interfaceName,
               interfaceExists(active.session.interfaceName) { throw BridgeFailure.rejected }
            try FileManager.default.removeItem(at: activeURL)
            try? FileManager.default.removeItem(at: root.appendingPathComponent("current.json"))
        }
        guard !FileManager.default.fileExists(atPath: directory.path), let path = options["--config"], let profile = UUID(uuidString: options["--profile"]!) else { throw BridgeFailure.rejected }
        let data = try readUserConfiguration(path)
        guard let text = String(data: data, encoding: .utf8) else { throw BridgeFailure.rejected }
        let configuration = try WGConfiguration(text: text)
        // Defence in depth: deny script-bearing additions regardless of parser implementation.
        for line in configuration.canonicalText.split(separator: "\n") {
            let key = line.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard !["preup", "postup", "predown", "postdown", "saveconfig"].contains(key) else { throw BridgeFailure.rejected }
        }
        try verifyTools()
        // Never rollback an already-existing interface that happens to share our short logical name.
        var priorMapping = stat()
        guard lstat("/var/run/wireguard/\(EngineUtilities.logicalName(for: id)).name", &priorMapping) != 0, errno == ENOENT else { throw BridgeFailure.rejected }
        try ensureDirectory(directory, create: true)
        try writeRootFile(Data(configuration.canonicalText.utf8), to: configurationURL)
        var raised = false, registered = false
        do {
            let result = try run("/opt/homebrew/bin/bash", ["/opt/homebrew/bin/wg-quick", "up", configurationURL.path])
            // Even failed wg-quick may have created a socket: rollback uses only our generated name.
            raised = true
            guard result.status == 0 else { throw BridgeFailure.failed }
            let interface = try readInterfaceName()
            let session = TunnelSession(id: id, profileID: profile, logicalName: EngineUtilities.logicalName(for: id), interfaceName: interface)
            guard EngineUtilities.valid(session) else { throw BridgeFailure.failed }
            let record = BridgeRecord(uid: uid, session: session)
            try writeRootFile(JSONEncoder().encode(record), to: recordURL)
            try writeRootFile(JSONEncoder().encode(record), to: activeURL)
            try writeRootFile(JSONEncoder().encode(session), to: root.appendingPathComponent("current.json"), owner: uid)
            registered = true
            try sample(session)
            try startMonitor()
            print(String(decoding: try JSONEncoder().encode(session), as: UTF8.self))
        } catch {
            if raised { _ = try? run("/opt/homebrew/bin/bash", ["/opt/homebrew/bin/wg-quick", "down", configurationURL.path]) }
            // If cleanup cannot remove a partially created interface, return its identity so
            // the app can persist ownership and offer an explicit disconnect.
            if let interface = try? readInterfaceName(), interfaceExists(interface) {
                let session = TunnelSession(id: id, profileID: profile, logicalName: EngineUtilities.logicalName(for: id), interfaceName: interface, startupIncomplete: true)
                let record = BridgeRecord(uid: uid, session: session)
                try writeRootFile(JSONEncoder().encode(record), to: recordURL)
                try writeRootFile(JSONEncoder().encode(record), to: activeURL)
                try writeRootFile(JSONEncoder().encode(session), to: root.appendingPathComponent("current.json"), owner: uid)
                try? sample(session)
                try? startMonitor()
                print(String(decoding: try JSONEncoder().encode(session), as: UTF8.self))
                return
            }
            if registered { try? FileManager.default.removeItem(at: activeURL); try? FileManager.default.removeItem(at: root.appendingPathComponent("current.json")) }
            try? FileManager.default.removeItem(at: directory)
            throw BridgeFailure.failed
        }
    }
    func stop() throws {
        try ensureDirectory(root, create: false); try ensureDirectory(directory, create: false)
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        let record: BridgeRecord = try readRootJSON(recordURL)
        guard record.uid == uid, record.session.id == id, EngineUtilities.valid(record.session) else { throw BridgeFailure.rejected }
        let active: BridgeRecord = try readRootJSON(activeURL)
        guard active.uid == uid, active.session == record.session else { throw BridgeFailure.rejected }
        if (try? readInterfaceName()) == record.session.interfaceName && interfaceExists(record.session.interfaceName) {
            let actual = try readInterfaceName()
            guard actual == record.session.interfaceName else { throw BridgeFailure.rejected }
            let result = try run("/opt/homebrew/bin/bash", ["/opt/homebrew/bin/wg-quick", "down", configurationURL.path])
            guard result.status == 0 else { throw BridgeFailure.failed }
            for _ in 0..<30 {
                if !interfaceExists(record.session.interfaceName) { break }; usleep(100_000)
            }
            guard !interfaceExists(record.session.interfaceName) else { throw BridgeFailure.failed }
        }
        try sample(record.session, alive: false)
        try FileManager.default.removeItem(at: activeURL)
        try? FileManager.default.removeItem(at: root.appendingPathComponent("current.json"))
        // Keep the final non-secret stats for the app; remove the root-owned private configuration.
        try? FileManager.default.removeItem(at: configurationURL)
    }
    func monitor() throws {
        try ensureDirectory(root, create: false); try ensureDirectory(directory, create: false)
        let record: BridgeRecord = try readRootJSON(recordURL)
        guard record.uid == uid, record.session.id == id, EngineUtilities.valid(record.session) else { throw BridgeFailure.rejected }
        while true {
            let alive = (try? readInterfaceName()) == record.session.interfaceName && interfaceExists(record.session.interfaceName)
            do { try sample(record.session, alive: alive) }
            catch {
                // Interface removal can race with wg reads. Retry and publish the terminal
                // sample on the next ownership check, rather than leaving permanent stale data.
                if alive { sleep(1); continue }
            }
            if !alive { break }
            sleep(1)
        }
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        if let active: BridgeRecord = try? readRootJSON(activeURL), active.session.id == id {
            try? FileManager.default.removeItem(at: activeURL)
            try? FileManager.default.removeItem(at: root.appendingPathComponent("current.json"))
        }
        try? FileManager.default.removeItem(at: configurationURL)
    }
    func startMonitor() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["monitor", "--uid", "\(uid)", "--id", id.uuidString]
        process.environment = Self.toolEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
    func sample(_ session: TunnelSession, alive: Bool = true) throws {
        let transfers = alive ? try run("/opt/homebrew/bin/wg", ["show", session.interfaceName, "transfer"]) : (status: Int32(0), output: "")
        let handshakes = alive ? try run("/opt/homebrew/bin/wg", ["show", session.interfaceName, "latest-handshakes"]) : (status: Int32(0), output: "")
        guard session.startupIncomplete || (transfers.status == 0 && handshakes.status == 0) else { throw BridgeFailure.failed }
        let stats = EngineUtilities.parseStatistics(interfaceName: session.interfaceName, transfers: transfers.output, handshakes: handshakes.output, alive: alive)
        try writeRootFile(JSONEncoder().encode(stats), to: directory.appendingPathComponent("stats.json"), owner: uid)
    }
    func readInterfaceName(for sessionID: UUID? = nil) throws -> String {
        let name = EngineUtilities.logicalName(for: sessionID ?? id)
        let mappingURL = URL(fileURLWithPath: "/var/run/wireguard/\(name).name")
        let data = try readRootFile(mappingURL)
        let interface = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard interface.range(of: "^utun[0-9]+$", options: .regularExpression) != nil else { throw BridgeFailure.failed }
        var info = stat()
        let socket = "/var/run/wireguard/\(interface).sock"
        var mappingInfo = stat()
        guard lstat(socket, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFSOCK,
              lstat(mappingURL.path, &mappingInfo) == 0,
              abs(info.st_mtimespec.tv_sec - mappingInfo.st_mtimespec.tv_sec) < 2 else { throw BridgeFailure.failed }
        return interface
    }
    func interfaceExists(_ interface: String) -> Bool {
        guard interface.range(of: "^utun[0-9]+$", options: .regularExpression) != nil else { return false }
        return (try? run("/sbin/ifconfig", [interface]).status) == 0
    }
    func verifyTools() throws {
        for path in ["/opt/homebrew/bin/bash", "/opt/homebrew/bin/wg", "/opt/homebrew/bin/wg-quick", "/opt/homebrew/bin/wireguard-go"] {
            guard FileManager.default.isExecutableFile(atPath: path) else { throw BridgeFailure.failed }
        }
        let bash = try run("/opt/homebrew/bin/bash", ["-c", "test \"${BASH_VERSINFO[0]}\" -ge 4"])
        guard bash.status == 0 else { throw BridgeFailure.failed }
    }
    func run(_ executable: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = args; process.environment = Self.toolEnvironment
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe
        // wg-quick may include config material in errors: discard it unconditionally.
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    func ensureDirectory(_ url: URL, create: Bool) throws {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            guard create, errno == ENOENT, mkdir(url.path, 0o711) == 0 else { throw BridgeFailure.rejected }
            guard lstat(url.path, &info) == 0 else { throw BridgeFailure.rejected }
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == 0, info.st_mode & 0o022 == 0 else { throw BridgeFailure.rejected }
    }
    func acquireLock() throws -> Int32 {
        let fd = open(root.appendingPathComponent("lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw BridgeFailure.rejected }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, flock(fd, LOCK_EX) == 0 else { close(fd); throw BridgeFailure.rejected }
        return fd
    }
    func readUserConfiguration(_ path: String) throws -> Data {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw BridgeFailure.rejected }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == uid, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size <= 1_048_576 else { throw BridgeFailure.rejected }
        return try readDescriptor(fd)
    }
    func readRootFile(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw BridgeFailure.rejected }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0, info.st_size <= 1_048_576 else { throw BridgeFailure.rejected }
        return try readDescriptor(fd)
    }
    func readDescriptor(_ fd: Int32) throws -> Data {
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count >= 0 else { throw BridgeFailure.failed }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
            guard result.count <= 1_048_576 else { throw BridgeFailure.rejected }
        }
        return result
    }
    func readRootJSON<T: Decodable>(_ url: URL) throws -> T { try JSONDecoder().decode(T.self, from: readRootFile(url)) }
    func writeRootFile(_ data: Data, to url: URL, owner: uid_t = 0) throws {
        // Parent is root-owned and not writable by the app: atomic replacement cannot follow a user symlink.
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw BridgeFailure.failed }
        defer { close(fd); unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard n > 0 else { throw BridgeFailure.failed }; offset += n
            }
        }
        guard fchmod(fd, 0o600) == 0, fchown(fd, owner, gid_t.max) == 0, rename(temporary.path, url.path) == 0 else { throw BridgeFailure.failed }
    }
}

do {
    let bridge = try Bridge(arguments: Array(CommandLine.arguments.dropFirst()))
    try bridge.execute()
} catch {
    // Never echo config, paths or lower-level exception details across the privilege boundary.
    FileHandle.standardError.write(Data("AetherBridge: 操作未完成。\n".utf8))
    exit(1)
}
