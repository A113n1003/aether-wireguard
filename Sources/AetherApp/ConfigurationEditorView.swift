import AppKit
import AetherCore
import SwiftUI

// 明确引用 property wrapper，兼容不包含新 State 宏插件的 Command Line Tools。
private typealias EditorState<Value> = SwiftUI.State<Value>

struct ConfigurationEditorView: View {
    let store: AppStore
    let editing: Bool
    @Environment(\.dismiss) private var dismiss
    @EditorState private var method = ImportMethod.file
    @EditorState private var name = ""
    @EditorState private var rawText = ""
    @EditorState private var fields = FormFields()
    @EditorState private var showsSecrets = false
    @EditorState private var importedFilename: String?
    @EditorState private var operationError: String?
    @EditorState private var editingID: UUID?
    @EditorState private var didLoad = false
    @EditorState private var viewingExample = false

    private enum ImportMethod: String, CaseIterable, Identifiable {
        case file = "文件导入", paste = "粘贴配置", form = "表单录入"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .file: "doc.badge.plus"; case .paste: "doc.on.clipboard"; case .form: "slider.horizontal.3" }
        }
    }
    private struct FormFields {
        var privateKey = ""
        var publicKey = ""
        var address = ""
        var endpoint = ""
        var allowedIPs = ""
        var dns = ""
        var presharedKey = ""
        var text: String {
            var lines = ["[Interface]", "PrivateKey = \(privateKey)", "Address = \(address)"]
            if !dns.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("DNS = \(dns)") }
            lines += ["", "[Peer]", "PublicKey = \(publicKey)"]
            if !endpoint.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("Endpoint = \(endpoint)") }
            if !presharedKey.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("PresharedKey = \(presharedKey)") }
            lines.append("AllowedIPs = \(allowedIPs)")
            return lines.joined(separator: "\n")
        }
        var hasInput: Bool {
            [privateKey, publicKey, address, endpoint, allowedIPs, dns, presharedKey].contains { !$0.isEmpty }
        }
    }
    private var configurationText: String { method == .form ? fields.text : rawText }
    private var hasInput: Bool { method == .form ? fields.hasInput : !rawText.isEmpty }
    private var parsed: WGConfiguration? { try? WGConfiguration(text: configurationText) }
    private var validationMessage: String? {
        guard hasInput else { return nil }
        do { _ = try WGConfiguration(text: configurationText); return nil }
        catch { return error.localizedDescription }
    }
    private var formRestriction: String? {
        guard !rawText.isEmpty else { return nil }
        guard let config = try? WGConfiguration(text: rawText) else {
            return "原文尚未通过校验，请先修正配置，再切换表单。"
        }
        if config.peers.count != 1 { return "此配置包含多个 Peer。请使用原文编辑，保留所有对端。" }
        if ["MTU =", "ListenPort =", "PersistentKeepalive ="].contains(where: config.canonicalText.contains) {
            return "此配置包含 MTU、ListenPort 或 PersistentKeepalive。请使用原文编辑，避免丢失高级字段。"
        }
        return nil
    }
    private var exampleIsBlocked: Bool { viewingExample && !store.isDemo }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsed != nil && !exampleIsBlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 14) {
                    Text("配置名称").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                    TextField("例如 Home Lab", text: $name).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("configuration.name")
                    if store.isDemo {
                        Label("演示配置仅存于内存", systemImage: "flask")
                            .font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }
                }
                methodPicker
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if method == .form { formContent } else { textContent }
                        validationContent
                    }.padding(.bottom, 10)
                }.scrollIndicators(.hidden)
            }.padding(.horizontal, 26).padding(.top, 19)
            footer
        }
        .frame(width: 750, height: 620)
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadExisting)
        .onChange(of: rawText) { _, value in
            operationError = nil
            if viewingExample && value != WGConfiguration.exampleText { viewingExample = false }
        }
        .onChange(of: fields.text) { _, _ in operationError = nil }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: editing ? "slider.horizontal.3" : "square.and.arrow.down")
                .font(.system(size: 21, weight: .light)).foregroundStyle(Palette.cyan)
                .frame(width: 43, height: 43).background(Palette.selected, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(editing ? "编辑隧道配置" : "添加一条新隧道").font(.system(size: 20, weight: .semibold))
                Text("导入或填写 WireGuard 配置")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            IconAction(symbol: "xmark", label: "关闭") { dismiss() }
        }.padding(.horizontal, 26).padding(.vertical, 22)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private var methodPicker: some View {
        HStack(spacing: 6) {
            ForEach(ImportMethod.allCases) { item in
                Button {
                    if item == .form {
                        guard formRestriction == nil else { return }
                        if !rawText.isEmpty { populateForm() }
                    } else if method == .form && fields.hasInput {
                        rawText = fields.text
                    }
                    method = item; operationError = nil
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(method == item ? Palette.cyan : Palette.muted)
                        .background(method == item ? Palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
                    .disabled(item == .form && formRestriction != nil)
                    .help(item == .form ? formRestriction ?? "适合单 Peer 的基本配置" : item.rawValue)
            }
        }.padding(4).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 11))
    }
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if method == .file {
                HStack(spacing: 14) {
                    Image(systemName: "doc.text").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.cyan)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(importedFilename ?? "选择 WireGuard 配置文件").font(.system(size: 13, weight: .medium))
                        Text("支持 .conf 文件")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("选择文件", action: chooseFile).buttonStyle(OutlineButtonStyle(accent: true))
                        .accessibilityIdentifier("configuration.chooseFile")
                }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Label("配置原文", systemImage: "curlybraces").font(.system(size: 12, weight: .medium))
                Spacer()
                if method == .paste {
                    Button { pasteConfiguration() } label: { Label("从剪贴板载入", systemImage: "doc.on.clipboard") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.cyan)
                        .accessibilityIdentifier("configuration.paste")
                }
                Button { showsSecrets.toggle() } label: {
                    Label(showsSecrets ? "隐藏密钥" : "显示密钥并编辑", systemImage: showsSecrets ? "eye.slash" : "eye")
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("configuration.revealSecrets")
            }
            Group {
                if showsSecrets {
                    TextEditor(text: $rawText)
                        .accessibilityLabel("WireGuard 配置原文，包含秘密密钥")
                        .accessibilityIdentifier("configuration.rawEditor")
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(rawText.isEmpty ? "导入或载入配置后，这里会显示隐藏密钥的预览。\n如需输入原文，请先点击「显示密钥并编辑」。" : maskedPreview(rawText))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10).foregroundStyle(rawText.isEmpty ? Palette.muted : Palette.text)
                    }.accessibilityLabel("配置预览，秘密密钥已隐藏")
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .scrollContentBackground(.hidden)
            .frame(height: method == .file ? 150 : 227)
            .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
            if let restriction = formRestriction { notice(restriction, symbol: "info.circle", color: Palette.muted) }
        }
    }
    private var formContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("一组 Interface，一个 Peer").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
                Button { showsSecrets.toggle() } label: {
                    Label(showsSecrets ? "隐藏密钥" : "显示密钥", systemImage: showsSecrets ? "eye.slash" : "eye")
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    field("PrivateKey", placeholder: "本机私钥 · 32 字节 Base64", binding: $fields.privateKey, secret: true)
                    field("PublicKey", placeholder: "对端公钥 · 32 字节 Base64", binding: $fields.publicKey)
                }
                GridRow {
                    field("Address", placeholder: "10.8.0.2/32, fd00::2/128", binding: $fields.address)
                    field("Endpoint · 可选", placeholder: "vpn.example.com:51820", binding: $fields.endpoint)
                }
                GridRow {
                    field("AllowedIPs", placeholder: "10.8.0.0/24, fd00::/64", binding: $fields.allowedIPs)
                    field("DNS · 可选", placeholder: "1.1.1.1, fd00::53", binding: $fields.dns)
                }
                GridRow {
                    field("PresharedKey · 可选", placeholder: "额外共享密钥", binding: $fields.presharedKey, secret: true)
                    notice("地址和路由使用 CIDR；多个值以逗号分隔。IPv6 Endpoint 使用 [地址]:端口。", symbol: "network", color: Palette.muted)
                }
            }
        }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
    }
    private func field(_ title: String, placeholder: String, binding: Binding<String>, secret: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            Group {
                if secret && !showsSecrets { SecureField(placeholder, text: binding) }
                else { TextField(placeholder, text: binding) }
            }.textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var validationContent: some View {
        if exampleIsBlocked {
            notice("这是格式示例，请导入自己的配置；演示模式可以保存示例。", symbol: "flask", color: Palette.amber)
        }
        if let operationError { notice(operationError, symbol: "exclamationmark.circle", color: Palette.red) }
        else if let validationMessage { notice(validationMessage, symbol: "exclamationmark.circle", color: Palette.red) }
        else if let config = parsed {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.shield").foregroundStyle(Palette.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置校验通过 · \(config.peers.count) 个 Peer").font(.system(size: 12, weight: .medium))
                    Text("\(config.addressSummary) · \(config.routeSummary)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }
                Spacer()
            }.padding(12).background(Palette.selected.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            ForEach(config.warnings, id: \.self) { notice($0, symbol: "exclamationmark.triangle", color: Palette.amber) }
        }
    }
    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 11)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var footer: some View {
        HStack {
            Button(store.isDemo ? "载入示例" : "查看格式示例", action: loadExample)
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .disabled(editing)
            Spacer()
            Button("取消") { dismiss() }.buttonStyle(OutlineButtonStyle()).keyboardShortcut(.cancelAction)
            Button(editing ? "保存修改" : "保存配置", action: save)
                .buttonStyle(PrimaryButtonStyle()).disabled(!canSave).opacity(canSave ? 1 : 0.45)
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("configuration.save")
        }.padding(.horizontal, 26).padding(.vertical, 17)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func loadExisting() {
        guard !didLoad else { return }; didLoad = true
        guard editing else { return }
        guard let profile = store.selectedProfile, let config = store.selectedConfiguration else {
            operationError = "找不到所选配置，请关闭窗口后重新选择。"; return
        }
        editingID = profile.id; name = profile.name; rawText = config.canonicalText
        method = .paste; populateForm()
    }
    private func populateForm() {
        guard let config = try? WGConfiguration(text: rawText), config.peers.count == 1 else { return }
        let values = config.canonicalText.components(separatedBy: "\n").reduce(into: [String: String]()) { result, line in
            guard let equal = line.firstIndex(of: "=") else { return }
            result[line[..<equal].trimmingCharacters(in: .whitespaces)] = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
        }
        let peer = config.peers[0]
        fields = FormFields(privateKey: values["PrivateKey"] ?? "", publicKey: peer.publicKey,
                            address: config.addressSummary, endpoint: peer.endpoint ?? "",
                            allowedIPs: peer.allowedIPs.joined(separator: ", "), dns: config.dns.joined(separator: ", "),
                            presharedKey: peer.presharedKey ?? "")
    }
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "导入 WireGuard 配置"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 262_145) ?? Data()
                guard data.count <= 262_144 else { throw AppError.message("文件超过 256 KB，请选择标准 .conf 配置文件。") }
                guard let text = String(data: data, encoding: .utf8) else { throw AppError.message("文件不是 UTF-8 文本，请检查配置文件编码。") }
                rawText = text; importedFilename = url.lastPathComponent; viewingExample = false
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                showsSecrets = false; operationError = nil
            } catch { operationError = error.localizedDescription }
        }
    }
    private func pasteConfiguration() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            operationError = "剪贴板中没有文本配置。"; return
        }
        guard text.utf8.count <= 262_144 else { operationError = "剪贴板内容超过 256 KB。"; return }
        rawText = text; viewingExample = false; operationError = nil; showsSecrets = false
    }
    private func loadExample() {
        rawText = WGConfiguration.exampleText; viewingExample = true; showsSecrets = false
        importedFilename = nil; method = .paste; operationError = nil
        if name.isEmpty { name = "格式示例" }
    }
    private func save() {
        guard !exampleIsBlocked else { return }
        guard !editing || editingID != nil else { operationError = "所选配置已不可用。"; return }
        do {
            let config = try WGConfiguration(text: configurationText)
            try store.save(name: name, text: config.canonicalText, editing: editing ? editingID : nil)
            dismiss()
        } catch { operationError = error.localizedDescription }
    }
    /// 不展示无效配置的原文，避免畸形字段或注释中的秘密漏入预览。
    private func maskedPreview(_ text: String) -> String {
        guard let config = try? WGConfiguration(text: text) else {
            return "配置未通过校验，安全预览暂不可用。\n查看下方错误，或点击「显示密钥并编辑」修正原文。"
        }
        return config.maskedText
    }
}
