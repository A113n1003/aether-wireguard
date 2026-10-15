import AppKit
import SwiftUI

typealias ViewState<Value> = SwiftUI.State<Value>

struct AlertPresentation: ViewModifier {
    @Bindable var store: AppStore
    func body(content: Content) -> some View {
        content.alert(store.alert?.title ?? "", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
            if let confirm = store.alert?.confirm {
                Button(confirm, role: store.alert?.destructive == true ? .destructive : nil) { store.acceptAlert() }
                Button("取消", role: .cancel) { store.pendingAction = nil; store.alert = nil }
            } else { Button("知道了", role: .cancel) { store.alert = nil } }
        } message: { Text(store.alert?.message ?? "") }
    }
}
struct AppPresentation: ViewModifier {
    @Bindable var store: AppStore
    func body(content: Content) -> some View {
        content.sheet(item: $store.sheet) { destination in
            switch destination {
            case .newConfiguration: ConfigurationEditorView(store: store, editing: false)
            case .editConfiguration: ConfigurationEditorView(store: store, editing: true)
            case .diagnostics: DiagnosticsView(store: store)
            case .settings: SettingsView(store: store)
            }
        }.modifier(AlertPresentation(store: store))
    }
}
struct SheetHeading: View {
    let title: String
    let subtitle: String
    var close: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 23, weight: .medium)); Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted) }
            Spacer(); IconAction(symbol: "xmark", label: "关闭", action: close)
        }
    }
}
struct SettingsView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.cyan)
                    .frame(width: 44, height: 44)
                    .background(Palette.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text("偏好设置").font(.system(size: 21, weight: .semibold))
                    Text("连接、界面与菜单栏").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                WindowCloseButton(action: { dismiss() }, label: "关闭偏好设置", hint: "关闭偏好设置")
            }.padding(.bottom, 24)

            VStack(spacing: 0) {
                settingRow(symbol: "network", title: "使用隧道 DNS", subtitle: "关闭后保留系统 DNS，重新连接后生效", value: $store.useTunnelDNS)
                Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1).padding(.leading, 64)
                settingRow(symbol: "menubar.rectangle", title: "菜单栏实时速率", subtitle: "在菜单栏显示当前下载速度", value: $store.showStatusText)
                Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1).padding(.leading, 64)
                settingRow(symbol: "waveform.path", title: "减少动态效果", subtitle: "关闭连接光环动画", value: $store.reduceMotion)
            }
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 1))

            Spacer(minLength: 20)
            Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1).padding(.bottom, 16)
            HStack(spacing: 8) {
                AetherMark(size: 20)
                Text("Aether \(Palette.appVersion)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 560, height: 440)
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(
            LinearGradient(colors: [Palette.cyan.opacity(0.32), Palette.line, Palette.line], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        .foregroundStyle(Palette.text).tint(Palette.cyan)
    }
    func settingRow(symbol: String, title: String, subtitle: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Palette.muted)
                .frame(width: 34, height: 34)
                .background(Palette.selected.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 16)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title)
        }.padding(.horizontal, 16).padding(.vertical, 17)
    }
}
struct DiagnosticsView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: "连接诊断", subtitle: "查看连接状态与事件日志") { dismiss() }
            Picker("诊断内容", selection: $tab) { Text("连接状态").tag(0); Text("脱敏配置").tag(1); Text("事件日志").tag(2) }.pickerStyle(.segmented)
            if tab == 0 {
                VStack(spacing: 0) {
                    row("虚拟接口", store.interfaceName ?? "尚未创建")
                    row("对端握手", store.lastHandshake.map { $0.formatted(date: .omitted, time: .standard) } ?? "尚未观测到")
                    row("路由", store.selectedConfiguration?.routeSummary ?? "尚无配置")
                    row("配置 DNS", store.selectedConfiguration?.dns.joined(separator: ", ") ?? "未指定")
                    row("DNS 设置", store.useTunnelDNS ? "使用隧道 DNS · 下次连接生效" : "保留系统 DNS · 下次连接生效")
                }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                if !store.errorMessage.isEmpty { Text(store.errorMessage).font(.system(size: 12)).foregroundStyle(Palette.amber) }
            } else if tab == 1 {
                ScrollView { Text(store.selectedConfiguration?.maskedText ?? "尚无配置").font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18) }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.events) { event in HStack(alignment: .top, spacing: 15) { Text(event.date.formatted(date: .omitted, time: .standard)).foregroundStyle(Palette.muted).monospacedDigit(); Text(event.text) }.font(.system(size: 11)) }
                        if store.events.isEmpty { Text("还没有连接事件").foregroundStyle(Palette.muted) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
            HStack { if store.isDemo { Text(store.footer).font(.system(size: 10)).foregroundStyle(Palette.amber) }; Spacer(); Button("完成") { dismiss() }.buttonStyle(PrimaryButtonStyle()) }
        }.padding(30).frame(width: 680, height: 550).background(Palette.background).foregroundStyle(Palette.text)
    }
    func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(title).foregroundStyle(Palette.muted).frame(width: 95, alignment: .leading); Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 12)).padding(13).overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 0.5) }
    }
}
