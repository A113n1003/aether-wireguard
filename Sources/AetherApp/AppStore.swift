import AppKit
import AetherCore
import Foundation
import Observation
import SwiftUI

struct TrafficPoint: Identifiable {
    let id = UUID()
    let download: Double
    let upload: Double
}
struct ConnectionEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}
enum ConnectionPhase: String {
    case disconnected, authorizing, awaitingHandshake, established, stopping, failure
    var title: String {
        switch self {
        case .disconnected: "未连接"
        case .authorizing: "正在连接"
        case .awaitingHandshake: "等待对端握手"
        case .established: "隧道已建立"
        case .stopping: "正在断开"
        case .failure: "连接需要处理"
        }
    }
    var color: Color {
        switch self {
        case .established: Palette.cyan
        case .authorizing, .awaitingHandshake, .stopping: Palette.amber
        case .failure: Palette.red
        case .disconnected: Palette.muted
        }
    }
}
enum SheetDestination: String, Identifiable {
    case newConfiguration, editConfiguration, diagnostics, settings
    var id: String { rawValue }
}
struct UserAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirm: String?
    var destructive = false
}

@MainActor @Observable final class AppStore {
    var profiles: [ProfileMetadata] = []
    var selectedID: UUID?
    var activeID: UUID?
    var phase: ConnectionPhase = .disconnected
    var sheet: SheetDestination?
    var alert: UserAlert?
    var isDemo = false
    var downloadRate: Double = 0
    var uploadRate: Double = 0
    var rxBytes: UInt64 = 0
    var txBytes: UInt64 = 0
    var lastHandshake: Date?
    var interfaceName: String?
    var errorMessage = ""
    var traffic: [TrafficPoint] = (0..<60).map { _ in TrafficPoint(download: 0, upload: 0) }
    var events: [ConnectionEvent] = []
    var toolsIssue: String?
    var toast: String?
    var showStatusText: Bool { didSet { UserDefaults.standard.set(showStatusText, forKey: "showStatusText") } }
    var reduceMotion: Bool { didSet { UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion") } }
    var demoFailure = false
    @ObservationIgnored let repository = ProfileRepository()
    @ObservationIgnored let engine = WireGuardEngine()
    @ObservationIgnored var configurations: [UUID: WGConfiguration] = [:]
    @ObservationIgnored var session: TunnelSession?
    @ObservationIgnored var lastStats: TunnelStatistics?
    @ObservationIgnored var operation: Task<Void, Never>?
    @ObservationIgnored var monitor: Task<Void, Never>?
    @ObservationIgnored var cancelRequested = false
    @ObservationIgnored var pendingAction: (() -> Void)?
    @ObservationIgnored var toastTask: Task<Void, Never>?
    @ObservationIgnored var demoTick = 0

    init() {
        showStatusText = UserDefaults.standard.bool(forKey: "showStatusText")
        reduceMotion = UserDefaults.standard.bool(forKey: "reduceMotion")
        if CommandLine.arguments.contains("--demo") { enableDemo() } else { loadProfiles() }
        monitor = Task { [weak self] in
            guard let self else { return }
            self.toolsIssue = await engine.availabilityIssue()
            if !isDemo {
                do {
                    if let recovered = try await engine.recoverSession() {
                        session = recovered; activeID = recovered.profileID
                        if profiles.contains(where: { $0.id == self.activeID }) { selectedID = activeID }
                        interfaceName = recovered.interfaceName; phase = recovered.startupIncomplete ? .failure : .awaitingHandshake
                        if recovered.startupIncomplete { errorMessage = "启动未完成，请断开隧道后检查配置与引擎" }
                        log("已恢复本客户端创建的隧道状态")
                    }
                } catch { notify("此前的隧道状态无法恢复，请在诊断中检查。") }
            }
            while !Task.isCancelled {
                await sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    var selectedProfile: ProfileMetadata? { profiles.first { $0.id == selectedID } }
    var activeProfile: ProfileMetadata? { profiles.first { $0.id == activeID } }
    var selectedConfiguration: WGConfiguration? { selectedID.flatMap { configurations[$0] } }
    var displayedPhase: ConnectionPhase { selectedID == activeID || activeID == nil ? phase : .disconnected }
    var isBusy: Bool { phase == .authorizing || phase == .stopping }
    var hasRunningTunnel: Bool { session != nil || (isDemo && activeID != nil && phase != .disconnected) }
    var selectedIsActive: Bool { selectedID != nil && selectedID == activeID }
    var detail: String {
        if let activeProfile, !selectedIsActive { return "\(activeProfile.name) 正在使用 · 连接此配置需要切换" }
        if cancelRequested { return "正在取消连接…" }
        switch displayedPhase {
        case .disconnected: return profiles.isEmpty ? "暂无配置" : "配置已保存"
        case .authorizing: return isDemo ? "演示：准备连接" : "正在准备连接…"
        case .awaitingHandshake: return "正在等待对端响应…"
        case .established:
            let age = lastHandshake.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
            return errorMessage.isEmpty ? "最近握手 \(age) 秒前" : errorMessage
        case .stopping: return "正在断开连接…"
        case .failure: return errorMessage
        }
    }
    var actionTitle: String {
        if profiles.isEmpty { return "导入配置" }
        if !selectedIsActive { return "连接隧道" }
        switch phase {
        case .established: return "断开连接"
        case .awaitingHandshake, .authorizing: return cancelRequested ? "正在取消…" : "取消连接"
        case .stopping: return "正在断开…"
        case .failure: return hasRunningTunnel ? "断开隧道" : "重试连接"
        case .disconnected: return "连接隧道"
        }
    }
    var footer: String { isDemo ? "演示模式 · 不修改系统网络" : "" }
    func configuration(for id: UUID) -> WGConfiguration? { configurations[id] }
    func loadProfiles() {
        do {
            profiles = try repository.list()
            configurations.removeAll()
            for profile in profiles { configurations[profile.id] = try repository.configuration(for: profile.id) }
            selectedID = profiles.first?.id
        } catch { showError("配置读取失败", error.localizedDescription) }
    }
    func save(name: String, text: String, editing id: UUID?) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppError.message("请填写配置名称。") }
        guard !profiles.contains(where: { $0.id != id && $0.name == name }) else { throw AppError.message("已存在同名配置，请换一个名称。") }
        if id == activeID && hasRunningTunnel { throw AppError.message("请先断开当前隧道，再保存修改。") }
        let config = try WGConfiguration(text: text)
        let existing = profiles.first { $0.id == id }
        let metadata = ProfileMetadata(id: id ?? UUID(), name: name, createdAt: existing?.createdAt ?? Date())
        if !isDemo { try repository.save(metadata: metadata, configuration: config) }
        if let index = profiles.firstIndex(where: { $0.id == metadata.id }) { profiles[index] = metadata } else { profiles.append(metadata) }
        configurations[metadata.id] = config; selectedID = metadata.id
        notify(isDemo ? "示例配置已保存到本次演示" : "配置已保存")
    }
    func deleteSelected() {
        guard let profile = selectedProfile else { return }
        guard profile.id != activeID || !hasRunningTunnel else { showError("请先断开隧道", "活动配置需要断开后才能删除。"); return }
        ask(title: "删除 \(profile.name)？", message: "该配置及保存的密钥会被移除。", confirm: "删除配置", destructive: true) { [weak self] in
            guard let self else { return }
            do {
                if !isDemo { try repository.delete(id: profile.id) }
                profiles.removeAll { $0.id == profile.id }; configurations[profile.id] = nil
                selectedID = profiles.first?.id; sheet = nil; notify("配置已删除")
            } catch { showError("删除失败", error.localizedDescription) }
        }
    }
    func performConnectionAction() {
        guard let selectedID else { sheet = .newConfiguration; return }
        if selectedIsActive && phase == .authorizing { cancelRequested = true; return }
        guard !isBusy else { return }
        if selectedIsActive && hasRunningTunnel { operation = Task { await disconnect() }; return }
        if hasRunningTunnel {
            let target = selectedID
            ask(title: "切换隧道？", message: "将先断开「\(activeProfile?.name ?? "当前隧道")」，再连接「\(selectedProfile?.name ?? "所选配置")」。", confirm: "切换并连接") { [weak self] in
                guard let self else { return }
                self.operation = Task { if await self.disconnect() { await self.connect(id: target) } }
            }
        } else if !isDemo && engine.requiresServiceSetup() {
            ask(title: "设置连接服务", message: "首次设置需要管理员授权，之后连接和断开无需重复输入密码。更新应用后可能需要重新授权。", confirm: "设置并连接") { [weak self] in
                guard let self else { return }
                self.operation = Task { await self.connect(id: selectedID) }
            }
        } else { operation = Task { await connect(id: selectedID) } }
    }
    func connect(id: UUID) async {
        guard let config = configurations[id], !isBusy else { return }
        selectedID = id; activeID = id; errorMessage = ""; cancelRequested = false
        rxBytes = 0; txBytes = 0; lastStats = nil; lastHandshake = nil
        traffic = (0..<60).map { _ in TrafficPoint(download: 0, upload: 0) }; events.removeAll()
        phase = .authorizing; log(isDemo ? "开始模拟连接" : "开始连接")
        if isDemo {
            try? await Task.sleep(for: .milliseconds(800))
            if cancelRequested { resetConnection(); return }
            phase = .awaitingHandshake; log("演示：引擎已启动，等待握手")
            try? await Task.sleep(for: .seconds(1))
            guard activeID == id else { return }
            if cancelRequested { resetConnection(); return }
            if demoFailure { phase = .failure; errorMessage = "尚未收到握手，请检查服务器、密钥和网络"; log("演示：等待握手超时，根因未确定"); return }
            phase = .established; lastHandshake = Date(); interfaceName = "utun · 示例"; log("演示：收到对端握手"); return
        }
        guard toolsIssue == nil else { phase = .failure; errorMessage = toolsIssue ?? "引擎不可用"; return }
        do {
            let started = try await engine.start(profileID: id, configuration: config)
            session = started; interfaceName = started.interfaceName; log("已创建 \(started.interfaceName)，等待对端握手")
            phase = started.startupIncomplete ? .failure : .awaitingHandshake
            if started.startupIncomplete { errorMessage = "启动未完成，请断开隧道后检查配置与引擎" }
            if cancelRequested { _ = await disconnect() }
        } catch {
            phase = cancelRequested ? .disconnected : .failure
            if cancelRequested { activeID = nil } else { errorMessage = error.localizedDescription }
            cancelRequested = false; log("连接操作未完成，请查看状态说明")
        }
    }
    @discardableResult func disconnect() async -> Bool {
        guard phase != .stopping else { return false }
        if phase == .authorizing { cancelRequested = true; return false }
        phase = .stopping; cancelRequested = false
        if isDemo { try? await Task.sleep(for: .milliseconds(350)); resetConnection(); log("演示：已断开"); return true }
        guard let session else { resetConnection(); return true }
        do {
            try await engine.stop(session); self.session = nil; resetConnection()
            log("已断开连接"); return true
        } catch { phase = .failure; errorMessage = error.localizedDescription; log("断开未完成，保留接口状态以便重试"); return false }
    }
    private func resetConnection() {
        activeID = nil; interfaceName = nil; phase = .disconnected; cancelRequested = false
        lastHandshake = nil; downloadRate = 0; uploadRate = 0; lastStats = nil
    }
    private func sample() async {
        if isDemo {
            if phase == .established {
                demoTick += 1
                downloadRate = (1.8 + 0.7 * sin(Double(demoTick)/5)) * 1_000_000
                uploadRate = (460 + 170 * sin(Double(demoTick)/3)) * 1_000
                rxBytes += UInt64(downloadRate); txBytes += UInt64(uploadRate)
                if demoTick % 24 == 0 { lastHandshake = Date() }
                addTraffic()
            }
            return
        }
        guard let session, phase != .stopping else { return }
        do {
            let next = try await engine.statistics(session)
            if let previous = lastStats {
                let interval = next.updatedAt.timeIntervalSince(previous.updatedAt)
                if interval > 0 {
                    downloadRate = Double(next.rxBytes >= previous.rxBytes ? next.rxBytes - previous.rxBytes : 0) / interval
                    uploadRate = Double(next.txBytes >= previous.txBytes ? next.txBytes - previous.txBytes : 0) / interval
                }
            }
            let newSample = lastStats?.updatedAt != next.updatedAt
            if !session.startupIncomplete { errorMessage = "" }
            rxBytes = next.rxBytes; txBytes = next.txBytes; lastHandshake = next.latestHandshake; lastStats = next
            if !next.alive {
                self.session = nil; phase = .failure; errorMessage = "隧道接口已停止，请重新连接"; downloadRate = 0; uploadRate = 0
            } else if next.latestHandshake != nil {
                if phase == .awaitingHandshake { log("已观测到对端握手") }
                if phase != .failure { phase = .established }
            }
            if Date().timeIntervalSince(next.updatedAt) > 8 { downloadRate = 0; uploadRate = 0; errorMessage = "状态采样暂时不可用，请检查诊断" }
            if newSample { addTraffic() }
        } catch { downloadRate = 0; uploadRate = 0; errorMessage = "状态采样暂时不可用，请检查诊断" }
    }
    private func addTraffic() {
        traffic.append(TrafficPoint(download: downloadRate, upload: uploadRate))
        if traffic.count > 60 { traffic.removeFirst(traffic.count - 60) }
    }
    private func enableDemo() {
        isDemo = true
        do {
            let config = try WGConfiguration(text: WGConfiguration.exampleText)
            let home = ProfileMetadata(name: "Home Lab"), tokyo = ProfileMetadata(name: "Tokyo Relay"), studio = ProfileMetadata(name: "Studio")
            profiles = [home, tokyo, studio]; configurations = [home.id: config, tokyo.id: config, studio.id: config]
            selectedID = home.id; activeID = home.id; phase = .established; lastHandshake = Date().addingTimeInterval(-8)
            interfaceName = "utun · 示例"; rxBytes = 128_000_000; txBytes = 24_000_000
            downloadRate = 2_480_000; uploadRate = 640_000
            traffic = (0..<60).map { i in TrafficPoint(download: (1.7+0.6*sin(Double(i)/7))*1_000_000, upload: (0.4+0.12*sin(Double(i)/4))*1_000_000) }
            log("演示模式，未创建真实网卡")
        } catch { showError("示例配置无效", error.localizedDescription) }
    }
    func ask(title: String, message: String, confirm: String, destructive: Bool = false, action: @escaping () -> Void) {
        pendingAction = action; alert = UserAlert(title: title, message: message, confirm: confirm, destructive: destructive)
    }
    func acceptAlert() { let action = pendingAction; pendingAction = nil; alert = nil; action?() }
    func showError(_ title: String, _ message: String) { pendingAction = nil; alert = UserAlert(title: title, message: message, confirm: nil) }
    func log(_ text: String) { events.append(ConnectionEvent(text: text)); if events.count > 80 { events.removeFirst() } }
    func notify(_ text: String) {
        toast = text; toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { toast = nil } }
    }
    static func rate(_ bytes: Double) -> String {
        if bytes >= 1_000_000 { return String(format: "%.2f MB/s", bytes / 1_000_000) }
        return String(format: "%.0f KB/s", bytes / 1_000)
    }
    static func total(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .decimal) }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
