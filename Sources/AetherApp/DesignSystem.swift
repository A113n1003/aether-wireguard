import SwiftUI

/// 主窗口与菜单栏共享的视觉语义。
enum Palette {
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    static let background = Color(red: 11/255, green: 16/255, blue: 24/255)
    static let sidebar = Color(red: 17/255, green: 23/255, blue: 32/255)
    static let panel = Color(red: 18/255, green: 27/255, blue: 39/255)
    static let selected = Color(red: 25/255, green: 40/255, blue: 58/255)
    static let line = Color(red: 42/255, green: 56/255, blue: 72/255)
    static let text = Color(red: 229/255, green: 237/255, blue: 247/255)
    static let muted = Color(red: 147/255, green: 163/255, blue: 184/255)
    static let cyan = Color(red: 112/255, green: 231/255, blue: 245/255)
    static let violet = Color(red: 188/255, green: 140/255, blue: 255/255)
    static let amber = Color(red: 234/255, green: 192/255, blue: 128/255)
    static let red = Color(red: 255/255, green: 146/255, blue: 151/255)
}

struct AetherMark: View {
    var size: CGFloat = 34
    var body: some View {
        Canvas { context, bounds in
            let scale = bounds.width / 48
            func path(_ points: [CGPoint]) -> Path {
                Path { p in
                    p.move(to: CGPoint(x: points[0].x * scale, y: points[0].y * scale))
                    for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale)) }
                    p.closeSubpath()
                }
            }
            context.fill(path([.init(x:24,y:3),.init(x:3,y:43),.init(x:15,y:39),.init(x:29,y:12)]), with: .color(Palette.cyan))
            context.fill(path([.init(x:28,y:17),.init(x:45,y:43),.init(x:33,y:39),.init(x:22,y:25)]), with: .color(Color(red:0.45,green:0.74,blue:0.84)))
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var accent: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .foregroundStyle(accent ? Palette.cyan : Palette.text)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(configuration.isPressed ? Palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent ? Palette.cyan.opacity(0.7) : Palette.line, lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 19).padding(.vertical, 11)
            .background(Palette.cyan.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct IconAction: View {
    let symbol: String
    let label: String
    var size: CGFloat = 30
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15)).frame(width: size, height: size) }
            .buttonStyle(.plain).foregroundStyle(Palette.muted).help(label).accessibilityLabel(label)
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.25), radius: 5)
    }
}

struct AddTunnelCard: View {
    var action: () -> Void
    @ViewState private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Palette.cyan)
                    .frame(width: 38, height: 38)
                    .background(Palette.cyan.opacity(hovering ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 12))
                Text("添加隧道").font(.system(size: 12, weight: .medium)).foregroundStyle(hovering ? Palette.cyan : Palette.text)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22)
            .background(hovering ? Palette.selected.opacity(0.6) : Palette.panel.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hovering ? Palette.cyan.opacity(0.6) : Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("添加隧道")
    }
}

struct WindowCloseButton: View {
    var action: () -> Void
    var label = "关闭窗口"
    var hint = "关闭窗口 · 可从菜单栏重新打开"
    @ViewState private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Palette.red : Palette.muted)
                .frame(width: 28, height: 28)
                .background(hovering ? Palette.red.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(hint)
    }
}
