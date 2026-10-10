import SwiftUI
import AetherCore

struct ConnectionOrb: View {
    let phase: ConnectionPhase
    var diameter: CGFloat = 230
    var reducedMotion = false
    var action: () -> Void
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reducedMotion || phase == .disconnected || phase == .failure)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = reducedMotion ? 0.5 : (sin(time * 1.8) + 1) / 2
            Button(action: action) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [phase.color.opacity(0.09), .clear], center: .center, startRadius: 15, endRadius: diameter / 2))
                    Circle().stroke(phase.color.opacity(0.10), lineWidth: 1).padding(2)
                    Circle().stroke(phase.color.opacity(0.25), lineWidth: 1).padding(14)
                    Circle().stroke(phase.color.opacity(0.55 + pulse * 0.25), lineWidth: 1.8).padding(25)
                        .shadow(color: phase.color.opacity(0.22), radius: 12)
                    Circle().trim(from: 0.08, to: phase == .established ? 0.96 : 0.73)
                        .stroke(phase.color.opacity(0.75), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .padding(33).rotationEffect(.degrees((phase == .authorizing || phase == .awaitingHandshake) && !reducedMotion ? time * 30 : -70))
                    Circle().fill(Palette.panel).overlay(Circle().stroke(phase.color.opacity(0.28), lineWidth: 1))
                        .frame(width: diameter * 0.35, height: diameter * 0.35)
                    Image(systemName: "power").font(.system(size: diameter * 0.15, weight: .light)).foregroundStyle(phase.color)
                }.frame(width: diameter, height: diameter).contentShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel("连接或断开所选隧道")
        }
    }
}
struct TrafficChart: View {
    let points: [TrafficPoint]
    var body: some View {
        Canvas { context, size in
            for i in 0...3 {
                let y = size.height * CGFloat(i) / 3
                var line = Path(); line.move(to: .init(x: 0, y: y)); line.addLine(to: .init(x: size.width, y: y))
                context.stroke(line, with: .color(Palette.line.opacity(0.55)), style: .init(lineWidth: 0.5, dash: [3, 5]))
            }
            guard points.count > 1 else { return }
            let maximum = max(1_000_000, (points.map { max($0.download, $0.upload) }.max() ?? 0) * 1.25)
            func draw(_ values: [Double], color: Color) {
                var line = Path()
                for (i, value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * size.width, y: size.height - CGFloat(value / maximum) * (size.height - 5))
                    if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
                }
                var area = line; area.addLine(to: .init(x: size.width, y: size.height)); area.addLine(to: .init(x: 0, y: size.height)); area.closeSubpath()
                context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.16), color.opacity(0.01)]), startPoint: .zero, endPoint: .init(x: 0, y: size.height)))
                context.stroke(line, with: .color(color), style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            draw(points.map(\.download), color: Palette.cyan)
            draw(points.map(\.upload), color: Palette.violet)
        }.accessibilityLabel("最近六十秒收发流量曲线")
    }
}
struct TrafficMetrics: View {
    let store: AppStore
    var compact = false
    var body: some View {
        HStack(alignment: .top) {
            metric("arrow.down", title: "下载", value: AppStore.rate(store.downloadRate), total: AppStore.total(store.rxBytes), color: Palette.cyan)
            Spacer()
            metric("arrow.up", title: "上传", value: AppStore.rate(store.uploadRate), total: AppStore.total(store.txBytes), color: Palette.violet)
        }
    }
    func metric(_ icon: String, title: String, value: String, total: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) { Image(systemName: icon).foregroundStyle(color); Text(title).foregroundStyle(Palette.muted) }.font(.system(size: 11))
            Text(value).font(.system(size: compact ? 19 : 25, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(color)
            if !compact { Text("本次累计 \(total)").font(.system(size: 11)).foregroundStyle(Palette.muted) }
        }
    }
}
struct MainWindowView: View {
    @Bindable var store: AppStore
    var closeWindow: () -> Void
    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            sidebar.frame(width: 228)
            Rectangle().fill(Palette.line.opacity(0.7)).frame(width: 1)
            VStack(spacing: 0) {
                header.padding(.horizontal, 36).padding(.top, 12).padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 14) {
                        connection(diameter: geometry.size.height < 760 ? 145 : 225)
                        if let config = store.selectedConfiguration { configurationStrip(config) }
                        trafficPanel
                    }.padding(.horizontal, 36).padding(.bottom, 16)
                }
                HStack {
                    if store.isDemo {
                        StatusDot(color: Palette.amber)
                        Text(store.footer).font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }
                    Spacer()
                    Button("诊断与日志") { store.sheet = .diagnostics }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(.horizontal, 36).padding(.vertical, 14).background(Palette.sidebar.opacity(0.55))
            }
        }.background(Palette.background).foregroundStyle(Palette.text)
            .overlay(alignment: .bottom) {
                if let toast = store.toast { Text(toast).font(.system(size: 12)).padding(12).background(Palette.selected, in: Capsule()).padding(.bottom, 50) }
            }
            .modifier(AppPresentation(store: store))
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) { AetherMark(); Text("AETHER").font(.system(size: 18, weight: .medium)).tracking(4) }.padding(.top, 12).padding(.bottom, 25)
            HStack {
                Text("我的隧道").font(.system(size: 11)).tracking(1)
                Spacer()
                if !store.profiles.isEmpty { IconAction(symbol: "plus", label: "导入配置") { store.sheet = .newConfiguration } }
            }.frame(height: 30).foregroundStyle(Palette.muted).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(store.profiles) { profile in
                        Button { store.selectedID = profile.id } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 7).fill(Palette.panel).frame(width: 32, height: 32).overlay(Image(systemName: "network").foregroundStyle(profile.id == store.activeID ? store.phase.color : Palette.muted))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(profile.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(profile.id == store.activeID ? store.phase.title : "WireGuard").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                                if profile.id == store.activeID { StatusDot(color: store.phase.color) }
                            }.padding(10).background(profile.id == store.selectedID ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                    if store.profiles.isEmpty { AddTunnelCard { store.sheet = .newConfiguration } }
                }
            }
            Spacer(minLength: 20)
            if !store.profiles.isEmpty {
                Button { store.sheet = .newConfiguration } label: { Label("导入配置", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(OutlineButtonStyle())
            }
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 20)
            Button { store.sheet = .settings } label: { Label("偏好设置", systemImage: "slider.horizontal.3") }.buttonStyle(.plain).foregroundStyle(Palette.muted).font(.system(size: 12)).padding(.bottom, 15)
            Text("WIREGUARD CLIENT   /   \(Palette.appVersion)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.65)).padding(.bottom, 23)
        }.padding(.horizontal, 18).background(Palette.sidebar)
    }
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aether").font(.system(size: 24, weight: .medium))
                Text("WireGuard 客户端").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                if store.isDemo { Text("演示").font(.system(size: 10)).foregroundStyle(Palette.amber).padding(.horizontal, 10).padding(.vertical, 5).overlay(Capsule().stroke(Palette.amber.opacity(0.35))) }
                IconAction(symbol: "square.and.pencil", label: "编辑所选配置", size: 28) { store.sheet = .editConfiguration }.disabled(store.selectedID == nil)
                IconAction(symbol: "ellipsis.circle", label: "连接诊断", size: 28) { store.sheet = .diagnostics }
                WindowCloseButton(action: closeWindow)
            }.frame(height: 28).padding(.top, 1)
        }
    }
    func connection(diameter: CGFloat) -> some View {
        VStack(spacing: 6) {
            ConnectionOrb(phase: store.displayedPhase, diameter: diameter, reducedMotion: store.reduceMotion, action: store.performConnectionAction)
            HStack(spacing: 8) { StatusDot(color: store.displayedPhase.color); Text(store.displayedPhase.title).font(.system(size: 24, weight: .medium)) }
            Text(store.detail).font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineLimit(3).frame(minHeight: 16)
            Button(store.actionTitle, action: store.performConnectionAction).buttonStyle(OutlineButtonStyle(accent: true)).frame(minWidth: 140).padding(.top, 8).disabled(store.phase == .stopping)
        }.frame(maxWidth: .infinity).padding(.bottom, 12)
    }
    func configurationStrip(_ config: AetherCore.WGConfiguration) -> some View {
        HStack(alignment: .top, spacing: 20) {
            field("隧道地址", config.addressSummary)
            Rectangle().fill(Palette.line).frame(width: 1, height: 34)
            field("对端", config.endpointSummary)
            Rectangle().fill(Palette.line).frame(width: 1, height: 34)
            field("路由", config.routeSummary)
        }.padding(16).frame(maxWidth: .infinity).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
    }
    func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            Text(value).font(.system(size: 11, design: .monospaced))
                .lineLimit(1).truncationMode(.tail).textSelection(.enabled)
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .help(value)
    }
    var trafficPanel: some View {
        VStack(spacing: 17) {
            HStack { Text(store.activeProfile.map { "\($0.name) · 流量概览" } ?? "流量概览").font(.system(size: 13, weight: .medium)); Spacer(); Text("最近 60 秒").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            TrafficMetrics(store: store)
            TrafficChart(points: store.traffic).frame(height: 60)
        }.padding(20).background(Palette.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MenuBarPopoverView: View {
    @Bindable var store: AppStore
    var openMain: () -> Void
    var openSheet: (SheetDestination) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack { AetherMark(size: 26); Text("AETHER").font(.system(size: 13, weight: .medium)).tracking(3); Spacer(); IconAction(symbol: "gearshape", label: "偏好设置") { openSheet(.settings) } }.padding(.bottom, 9)
            Text(store.selectedProfile?.name ?? "Aether").font(.system(size: 19, weight: .medium)).lineLimit(1)
            ConnectionOrb(phase: store.displayedPhase, diameter: 128, reducedMotion: store.reduceMotion, action: store.performConnectionAction).padding(.vertical, 2)
            HStack(spacing: 7) { StatusDot(color: store.displayedPhase.color); Text(store.displayedPhase.title).font(.system(size: 19, weight: .medium)) }
            Text(store.detail).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.center).frame(height: 26).padding(.top, 6)
            Button(store.actionTitle, action: store.performConnectionAction).buttonStyle(OutlineButtonStyle(accent: true)).padding(.top, 9).disabled(store.phase == .stopping)
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 10)
            TrafficMetrics(store: store, compact: true)
            TrafficChart(points: store.traffic).frame(height: 36).padding(.top, 10)
            HStack { Text("切换隧道").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); Text("\(store.profiles.count) 个配置").font(.system(size: 9)).foregroundStyle(Palette.muted) }.padding(.top, 12).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(store.profiles) { profile in
                        Button { store.selectedID = profile.id; if profile.id != store.activeID { store.performConnectionAction() } } label: {
                            HStack { StatusDot(color: profile.id == store.activeID ? store.phase.color : Palette.muted); Text(profile.name).font(.system(size: 12)); Spacer(); Image(systemName: profile.id == store.activeID ? "checkmark" : "chevron.right").font(.system(size: 10)).foregroundStyle(profile.id == store.activeID ? Palette.cyan : Palette.muted) }.padding(.horizontal, 10).padding(.vertical, 9).background(profile.id == store.selectedID ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    if store.profiles.isEmpty { Text("暂无配置").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(10) }
                }
            }.frame(height: min(72, max(38, CGFloat(store.profiles.count) * 36)))
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 9)
            HStack(spacing: 10) {
                Button(action: openMain) { Label("打开主窗口", systemImage: "arrow.up.forward.square").frame(maxWidth: .infinity) }.buttonStyle(OutlineButtonStyle())
                Button { openSheet(.newConfiguration) } label: { Label("导入配置", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(OutlineButtonStyle())
            }
            if store.isDemo { Text(store.footer).font(.system(size: 9)).foregroundStyle(Palette.amber).padding(.top, 9) }
        }.padding(18).frame(width: 360, height: store.isDemo ? 620 : 596).background(Palette.background).foregroundStyle(Palette.text)
            .modifier(AlertPresentation(store: store))
    }
}
