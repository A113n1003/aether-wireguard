import AppKit
import SwiftUI

@main
struct AetherApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AetherAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

/// 无原生标题栏的窗口仍需要接收键盘输入，并参与主窗口切换。
final class AetherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class AetherAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = AppStore()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        installMenu()
        window = AetherWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 825), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = "Aether"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 720)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: MainWindowView(store: store, closeWindow: { [weak self] in self?.window.close() })
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line.opacity(0.65), lineWidth: 1))
            .preferredColorScheme(.dark))
        window.center()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusImage()
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Aether · 点击打开连接面板"
            button.setAccessibilityLabel("Aether 连接面板")
        }
        popover.contentSize = NSSize(width: 360, height: 620)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(store: store, openMain: { [weak self] in self?.showMain() }, openSheet: { [weak self] destination in self?.showSheet(destination) }).preferredColorScheme(.dark))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
        showMain()
        if CommandLine.arguments.contains("--show-popover") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.togglePopover() } }
    }
    func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let left = NSBezierPath(); left.move(to: NSPoint(x: 9, y: 17)); left.line(to: NSPoint(x: 1, y: 2)); left.line(to: NSPoint(x: 5, y: 3)); left.line(to: NSPoint(x: 11, y: 13)); left.close(); left.fill()
            let right = NSBezierPath(); right.move(to: NSPoint(x: 10, y: 10)); right.line(to: NSPoint(x: 17, y: 2)); right.line(to: NSPoint(x: 12, y: 3)); right.line(to: NSPoint(x: 7, y: 7)); right.close(); right.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
    func refreshStatus() {
        guard let button = statusItem?.button else { return }
        if store.showStatusText { button.title = "  ↓ \(AppStore.rate(store.downloadRate))"; button.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium) }
        else { button.title = "" }
        button.toolTip = "Aether · \(store.phase.title)\(store.isDemo ? " · 演示" : "")"
    }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        popover.contentSize = NSSize(width: 360, height: store.isDemo ? 620 : 596)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc func showMain() {
        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showSheet(_ destination: SheetDestination) { showMain(); store.sheet = destination }
    @objc func importConfiguration() { showSheet(.newConfiguration) }
    @objc func preferences() { showSheet(.settings) }
    @objc func diagnostics() { showSheet(.diagnostics) }
    @objc func connectAction() { store.performConnectionAction() }
    @objc func closeMainWindow() { window.close() }
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        popover.performClose(nil)
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store.isDemo || (!store.hasRunningTunnel && !store.isBusy) { return .terminateNow }
        showMain()
        let alert = NSAlert()
        alert.messageText = "退出 Aether？"
        alert.informativeText = store.isBusy ? "网络操作尚未完成。请完成或取消授权，并等待操作结束。" : "关闭主窗口会保留菜单栏面板。退出应用时，你可以选择继续保留隧道或先断开。"
        if store.isBusy { alert.addButton(withTitle: "返回应用"); alert.runModal(); return .terminateCancel }
        alert.addButton(withTitle: "断开并退出")
        alert.addButton(withTitle: "保留连接并退出")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { let success = await store.disconnect(); NSApp.reply(toApplicationShouldTerminate: success) }
            return .terminateLater
        case .alertSecondButtonReturn: return .terminateNow
        default: return .terminateCancel
        }
    }
    func installMenu() {
        let root = NSMenu()
        let applicationItem = NSMenuItem(); root.addItem(applicationItem)
        let application = NSMenu(); applicationItem.submenu = application
        application.addItem(withTitle: "关于 Aether", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        item("偏好设置…", action: #selector(preferences), key: ",", into: application)
        application.addItem(.separator())
        application.addItem(withTitle: "退出 Aether", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let tunnelItem = NSMenuItem(); tunnelItem.title = "隧道"; root.addItem(tunnelItem)
        let tunnel = NSMenu(title: "隧道"); tunnelItem.submenu = tunnel
        item("打开主窗口", action: #selector(showMain), key: "1", into: tunnel)
        item("关闭主窗口", action: #selector(closeMainWindow), key: "w", into: tunnel)
        item("显示连接面板", action: #selector(togglePopover), key: "m", into: tunnel, modifiers: [.command, .shift])
        item("导入配置…", action: #selector(importConfiguration), key: "o", into: tunnel)
        item("连接 / 断开", action: #selector(connectAction), key: "d", into: tunnel)
        item("连接诊断…", action: #selector(diagnostics), key: "l", into: tunnel)
        let editItem = NSMenuItem(); editItem.title = "编辑"; root.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = root
    }
    func item(_ title: String, action: Selector, key: String, into menu: NSMenu, modifiers: NSEvent.ModifierFlags = [.command]) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
    }
}
