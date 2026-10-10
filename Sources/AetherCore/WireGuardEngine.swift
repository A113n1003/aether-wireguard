import Foundation
import Darwin
import Carbon

public struct TunnelSession: Codable, Sendable, Equatable {
    public let id: UUID
    public let profileID: UUID
    public let logicalName: String
    public let interfaceName: String
    public let startupIncomplete: Bool
    public init(id: UUID, profileID: UUID, logicalName: String, interfaceName: String, startupIncomplete: Bool = false) {
        self.id = id; self.profileID = profileID; self.logicalName = logicalName; self.interfaceName = interfaceName
        self.startupIncomplete = startupIncomplete
    }
    private enum CodingKeys: String, CodingKey { case id, profileID, logicalName, interfaceName, startupIncomplete }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        profileID = try values.decode(UUID.self, forKey: .profileID)
        logicalName = try values.decode(String.self, forKey: .logicalName)
        interfaceName = try values.decode(String.self, forKey: .interfaceName)
        startupIncomplete = try values.decodeIfPresent(Bool.self, forKey: .startupIncomplete) ?? false
    }
}

public struct TunnelStatistics: Codable, Sendable, Equatable {
    public let interfaceName: String
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public let latestHandshake: Date?
    public let updatedAt: Date
    public let alive: Bool
    public init(interfaceName: String, rxBytes: UInt64, txBytes: UInt64, latestHandshake: Date?, updatedAt: Date, alive: Bool) {
        self.interfaceName = interfaceName; self.rxBytes = rxBytes; self.txBytes = txBytes
        self.latestHandshake = latestHandshake; self.updatedAt = updatedAt; self.alive = alive
    }
}

public enum EngineError: Error, LocalizedError, Sendable {
    case unavailable(String), authorizationCancelled, operationFailed, invalidSession, staleStatistics
    public var errorDescription: String? {
        switch self {
        case .unavailable(let explanation): explanation
        case .authorizationCancelled: "已取消管理员授权，连接操作未完成。"
        case .operationFailed: "WireGuard 操作未完成。请检查配置、管理员授权和本机工具。"
        case .invalidSession: "隧道会话记录无效。"
        case .staleStatistics: "暂时无法取得隧道状态，请稍后重试。"
        }
    }
}

/// Helpers shared with tests and the privileged bridge; AppleEvent creation stays on the main thread.
public enum EngineUtilities {
    // Keep the compiled script unchanged: macOS authorizes a script, not each Bridge command.
    public static let authorizationScriptSource = """
    on authorize_command(commandText)
        return do shell script commandText with administrator privileges without altering line endings
    end authorize_command
    """
    @MainActor public static func authorizationEvent(command: String) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: NSAppleEventDescriptor.currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "authorize_command"), forKeyword: AEKeyword(keyASSubroutineName))
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: command), at: 1)
        event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        return event
    }
    public static func authorizationError(number: Int?) -> EngineError {
        number == -128 ? .authorizationCancelled : .operationFailed
    }
    public static func logicalName(for id: UUID) -> String {
        "ae" + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10)
    }
    public static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func appleScriptQuote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    public static func runtimeDirectory(uid: uid_t) -> URL { URL(fileURLWithPath: "/var/run/aether-\(uid)", isDirectory: true) }
    public static func statisticsURL(session: TunnelSession, uid: uid_t) -> URL {
        runtimeDirectory(uid: uid).appendingPathComponent(session.id.uuidString, isDirectory: true).appendingPathComponent("stats.json")
    }
    public static func valid(_ session: TunnelSession) -> Bool {
        session.logicalName == logicalName(for: session.id) && session.interfaceName.range(of: "^utun[0-9]+$", options: .regularExpression) != nil
    }
    public static func parseStatistics(interfaceName: String, transfers: String, handshakes: String, now: Date = Date(), alive: Bool = true) -> TunnelStatistics {
        var rx: UInt64 = 0, tx: UInt64 = 0, newest: TimeInterval = 0
        for line in transfers.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            if fields.count == 3, let received = UInt64(fields[1]), let sent = UInt64(fields[2]) {
                let r = rx.addingReportingOverflow(received), t = tx.addingReportingOverflow(sent)
                rx = r.overflow ? UInt64.max : r.partialValue; tx = t.overflow ? UInt64.max : t.partialValue
            }
        }
        for line in handshakes.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            if fields.count == 2, let stamp = TimeInterval(fields[1]), stamp.isFinite, stamp > 0 { newest = max(newest, stamp) }
        }
        return TunnelStatistics(interfaceName: interfaceName, rxBytes: rx, txBytes: tx, latestHandshake: newest > 0 ? Date(timeIntervalSince1970: newest) : nil, updatedAt: now, alive: alive)
    }
}

/// NSAppleScript is confined to the main thread and one unchanged instance.
/// System authorization expires (normally after five minutes); no password is retained by Aether.
@MainActor private final class AdministratorAuthorization {
    static let shared = AdministratorAuthorization()
    private var script: NSAppleScript?
    private init() {}

    func execute(command: String) throws -> String {
        if script == nil {
            guard let candidate = NSAppleScript(source: EngineUtilities.authorizationScriptSource) else { throw EngineError.operationFailed }
            var error: NSDictionary?
            guard candidate.compileAndReturnError(&error) else { throw EngineError.operationFailed }
            script = candidate
        }
        var error: NSDictionary?
        let result = script?.executeAppleEvent(EngineUtilities.authorizationEvent(command: command), error: &error)
        guard error == nil, let output = result?.stringValue else {
            // Do not expose AppleScript messages: shell stderr may contain configuration details.
            throw EngineUtilities.authorizationError(number: (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public actor WireGuardEngine {
    private let uid = getuid()
    private let root: URL
    private var current: TunnelSession?
    private var busy = false
    public init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aether/runtime", isDirectory: true)
    }
    public func toolchainDescription() -> String { "wireguard-go · wg-quick · Homebrew Bash 4+ · 系统管理员授权" }
    public func availabilityIssue() -> String? {
        for path in ["/opt/homebrew/bin/bash", "/opt/homebrew/bin/wg", "/opt/homebrew/bin/wg-quick", "/opt/homebrew/bin/wireguard-go"] {
            if !FileManager.default.isExecutableFile(atPath: path) { return "缺少 \(URL(fileURLWithPath: path).lastPathComponent)。需要安装 Homebrew bash、wireguard-tools、wireguard-go。" }
        }
        return helperURL() == nil ? "未找到 AetherBridge。请使用完整 Aether.app。" : nil
    }
    public func start(profileID: UUID, configuration: WGConfiguration) async throws -> TunnelSession {
        guard !busy, current == nil else { throw EngineError.operationFailed }
        if let issue = availabilityIssue() { throw EngineError.unavailable(issue) }
        guard let helper = helperURL() else { throw EngineError.operationFailed }
        busy = true; defer { busy = false }
        let id = UUID()
        try ensureUserDirectory()
        let input = root.appendingPathComponent("\(id.uuidString).conf")
        try secureWrite(Data(configuration.canonicalText.utf8), to: input)
        defer { try? FileManager.default.removeItem(at: input) }
        let args = ["start", "--uid", "\(uid)", "--id", id.uuidString, "--profile", profileID.uuidString, "--config", input.path]
        let output = try await authorize(helper: helper, arguments: args)
        guard let session = try? JSONDecoder().decode(TunnelSession.self, from: Data(output.utf8)), session.id == id, session.profileID == profileID, EngineUtilities.valid(session) else { throw EngineError.operationFailed }
        // Once the helper reports success, keep a recoverable registry even if the caller task was cancelled.
        current = session
        do { try secureWrite(JSONEncoder().encode(session), to: registryURL) }
        catch {
            // A live session must never disappear from app ownership merely because persistence failed.
            if (try? await authorize(helper: helper, arguments: ["stop", "--uid", "\(uid)", "--id", id.uuidString])) != nil {
                current = nil; throw EngineError.operationFailed
            }
            // The helper also publishes a recoverable, non-secret ownership record.
            return session
        }
        if Task.isCancelled { try await stop(session); throw CancellationError() }
        return session
    }
    public func stop(_ session: TunnelSession) async throws {
        guard EngineUtilities.valid(session), let helper = helperURL() else { throw EngineError.invalidSession }
        _ = try await authorize(helper: helper, arguments: ["stop", "--uid", "\(uid)", "--id", session.id.uuidString])
        current = nil
        try? FileManager.default.removeItem(at: registryURL)
    }
    public func statistics(_ session: TunnelSession) async throws -> TunnelStatistics {
        guard EngineUtilities.valid(session) else { throw EngineError.invalidSession }
        let url = EngineUtilities.statisticsURL(session: session, uid: uid)
        let result = try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TunnelStatistics.self, from: data)
        }.value
        guard result.interfaceName == session.interfaceName,
              !result.alive || abs(Date().timeIntervalSince(result.updatedAt)) < 10 else { throw EngineError.staleStatistics }
        if !result.alive, current?.id == session.id {
            current = nil
            try? FileManager.default.removeItem(at: registryURL)
        }
        return result
    }
    public func recoverSession() async throws -> TunnelSession? {
        if let current { return current }
        let published = EngineUtilities.runtimeDirectory(uid: uid).appendingPathComponent("current.json")
        let candidate = FileManager.default.fileExists(atPath: registryURL.path) ? registryURL : published
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        guard let data = try? Data(contentsOf: candidate), let session = try? JSONDecoder().decode(TunnelSession.self, from: data), EngineUtilities.valid(session) else { throw EngineError.invalidSession }
        if let stats = try? await statistics(session), !stats.alive {
            try? FileManager.default.removeItem(at: registryURL); return nil
        }
        // Missing or stale statistics are a diagnostic state, not evidence that the tunnel was removed.
        current = session; return session
    }
    private var registryURL: URL { root.appendingPathComponent("session.json") }
    private func helperURL() -> URL? {
        let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/AetherBridge"), URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("AetherBridge")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    private func ensureUserDirectory() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == uid else { throw EngineError.operationFailed }
        chmod(root.path, 0o700)
    }
    private func secureWrite(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw EngineError.operationFailed }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == uid, info.st_nlink == 1 else { throw EngineError.operationFailed }
        guard fchmod(fd, 0o600) == 0, ftruncate(fd, 0) == 0 else { throw EngineError.operationFailed }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard n > 0 else { throw EngineError.operationFailed }; offset += n
            }
        }
    }
    private func authorize(helper: URL, arguments: [String]) async throws -> String {
        let command = ([helper.path] + arguments).map(EngineUtilities.shellQuote).joined(separator: " ")
        return try await AdministratorAuthorization.shared.execute(command: command)
    }
}
