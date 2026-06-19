import SwiftUI
import ServiceManagement

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @ObservedObject var settings = Settings.shared
    @ObservedObject var historyManager = HistoryManager.shared
    @ObservedObject var dictionary = DictionaryStore.shared
    @ObservedObject var styleStore = StyleProfileStore.shared
    @ObservedObject var notebook = NotebookStore.shared

    @State private var showApiKey = false
    @State private var showOpenAIKey = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gear") }

            tierTab
                .tabItem { Label("档位", systemImage: "slider.horizontal.3") }

            dictionaryTab
                .tabItem { Label("词典", systemImage: "character.book.closed") }

            personalizeTab
                .tabItem { Label("个性化", systemImage: "person.crop.circle") }

            historyTab
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }

            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 560)
    }

    // MARK: - 通用

    private var generalTab: some View {
        Form {
            // 触发与启动
            Section {
                Picker("触发快捷键", selection: $settings.hotkey) {
                    ForEach(Settings.hotkeyPresets, id: \.id) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
                .onChange(of: settings.hotkey) { _, _ in
                    appDelegate.registerHotkey()
                }

                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("[PunkType] Launch at login failed: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Toggle("开始 / 停止提示音", isOn: $settings.playSounds)
            } header: {
                Text("触发")
            } footer: {
                Text("按一下快捷键开始录音，再按一下停止。选中文字时按快捷键会进入命令模式。" +
                     (settings.hotkey == "fn"
                      ? "\n\n用 🌐 Fn 键时，若按 Fn 会弹出表情或听写，请到「系统设置 → 键盘 →『按下 🌐 键时』」改为「无操作」。"
                      : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 输出档位（当前档；每档的引擎/模型/流式在「档位」标签里配）
            Section {
                Picker("当前档位", selection: $settings.tier) {
                    ForEach(Settings.tiers, id: \.self) { tier in
                        Text(Settings.tierLabels[tier] ?? tier).tag(tier)
                    }
                }
                Toggle("按应用自动调整语气（App 感知）", isOn: $settings.appAware)
            } header: {
                Text("输出")
            } footer: {
                Text(tierFooter + "\n每一档的识别引擎、模型、流式输出、提示词都可在「档位」标签里单独自定义。" +
                     "\nApp 感知：自动识别你正在哪个应用输入，聊天软件用口语、邮件更正式、代码/终端保留术语。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 命令 / 翻译模型（非档位，单独配）
            Section {
                Picker("命令 / 翻译模型", selection: $settings.heavyModel) {
                    ForEach(Settings.supportedModels, id: \.self) { model in
                        Text(Settings.modelLabels[model] ?? model).tag(model)
                    }
                }
                Picker("识别语言", selection: $settings.language) {
                    ForEach(Settings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            } header: {
                Text("通用")
            } footer: {
                Text("命令 / 翻译模型用于「选中文字命令」。识别语言对所有档位生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // DeepSeek 密钥
            Section {
                LabeledContent("DeepSeek 密钥") {
                    HStack(spacing: 6) {
                        Group {
                            if showApiKey {
                                TextField("sk-...", text: $settings.apiKey)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("sk-...", text: $settings.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                        Button(action: { showApiKey.toggle() }) {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                LabeledContent("连接测试") {
                    HStack(spacing: 8) {
                        Button(action: testApiKey) {
                            if isTesting {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                            }
                            Text("测试")
                        }
                        .disabled(isTesting || !settings.isConfigured)

                        if let result = testResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.contains("✓") ? Color.green : Color.red)
                        }
                    }
                }
            } header: {
                Text("DeepSeek 密钥")
            } footer: {
                Text("前往 platform.deepseek.com 获取密钥。润色 / 格式 / 命令档位都需要它。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // OpenAI 密钥（可选）
            Section {
                LabeledContent("OpenAI 密钥") {
                    HStack(spacing: 6) {
                        Group {
                            if showOpenAIKey {
                                TextField("sk-...", text: $settings.openaiKey)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("sk-...", text: $settings.openaiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                        Button(action: { showOpenAIKey.toggle() }) {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                TextField("转写模型", text: $settings.openaiModel)
                    .font(.system(.caption, design: .monospaced))
            } header: {
                Text("OpenAI 密钥（Whisper，可选）")
            } footer: {
                Text("仅在使用 Whisper 云端转写时需要。默认模型 gpt-4o-mini-transcribe。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 记事本
            Section {
                Toggle("记事本（自动收录每次口述）", isOn: $settings.notebookEnabled)
                if !notebook.knownApps.isEmpty {
                    DisclosureGroup("收录范围（勾选 = 收录该应用）") {
                        ForEach(notebook.knownApps.sorted(by: { $0.value < $1.value }), id: \.key) { bid, name in
                            Toggle(name, isOn: Binding(
                                get: { !notebook.isExcluded(bundleID: bid) },
                                set: { notebook.setExcluded(bid, excluded: !$0) }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        }
                    }
                }
            } header: {
                Text("记事本")
            } footer: {
                Text("每次出字会自动收进本地记事本（⌥⌘N 打开）。默认收录所有应用，微信默认不收录；用过的应用会出现在上面的勾选列表里。完全本地。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 高级
            Section("高级") {
                TextField("接口地址", text: $settings.apiEndpoint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var tierFooter: String {
        switch settings.tier {
        case "fast":   return "⚡ 极速：识别原文直出，不经过 AI，零等待。"
        case "format": return "📄 格式：清理口语并自动按体裁排版（邮件 / 汇报 / 纪要 / 待办），使用更强的模型。"
        default:        return "✨ 润色：清理语气词、结巴、语序，保留你的口语风格。"
        }
    }

    // MARK: - 档位（每档：识别引擎 + 模型 + 流式 + 提示词）

    @State private var editingTier = "polish"

    private var tierTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $editingTier) {
                Text("⚡ 极速").tag("fast")
                Text("✨ 润色").tag("polish")
                Text("📄 格式").tag("format")
                Text("🎯 命令").tag("command")
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Form {
                if editingTier != "command" {
                    Section("识别") {
                        Picker("识别引擎", selection: sttBinding) {
                            Text("本机识别（稳定，离线）").tag("local")
                            if #available(macOS 26.0, *) {
                                Text("Apple 快速识别（macOS 26，更快）").tag("apple-fast")
                            }
                            Text("Whisper 云端（更准，需 OpenAI Key）").tag("whisper")
                        }
                    }
                }

                if editingTier == "polish" || editingTier == "format" {
                    Section("加工") {
                        Picker("AI 模型", selection: modelBinding) {
                            ForEach(Settings.supportedModels, id: \.self) { m in
                                Text(Settings.modelLabels[m] ?? m).tag(m)
                            }
                        }
                        Toggle("流式输出（边生成边打字，更快）", isOn: streamBinding)
                    }
                }

                if editingTier == "fast" {
                    Section {
                        Text("极速档不经过 AI，识别完直接出字，零等待。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if editingTier != "fast" {
                    Section {
                        TextEditor(text: promptBinding)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                        HStack {
                            Button("恢复默认提示词") { resetPrompt() }
                                .buttonStyle(.link)
                            Spacer()
                            Text("\(promptBinding.wrappedValue.count) 字")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("提示词")
                    } footer: {
                        Text(tierPromptHint).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
    }

    private var sttBinding: Binding<String> {
        switch editingTier {
        case "fast":   return $settings.sttFast
        case "format": return $settings.sttFormat
        default:        return $settings.sttPolish
        }
    }

    private var modelBinding: Binding<String> {
        editingTier == "format" ? $settings.modelFormat : $settings.modelPolish
    }

    private var streamBinding: Binding<Bool> {
        editingTier == "format" ? $settings.streamFormat : $settings.streamPolish
    }

    private var promptBinding: Binding<String> {
        switch editingTier {
        case "format":  return $settings.formatPrompt
        case "command": return $settings.commandPrompt
        default:         return $settings.systemPrompt
        }
    }

    private func resetPrompt() {
        switch editingTier {
        case "format":  settings.formatPrompt = Settings.defaultFormatPrompt
        case "command": settings.commandPrompt = Settings.defaultCommandPrompt
        default:         settings.systemPrompt = Settings.defaultPrompt
        }
    }

    private var tierPromptHint: String {
        switch editingTier {
        case "format":  return "格式档：清理口语并按体裁（邮件 / 汇报 / 纪要 / 待办）自动排版。"
        case "command": return "命令模式：宿主 App 中有选中文字时，口述指令处理选中内容。"
        default:         return "润色档：清理语气词、结巴、语序，保留口语风格。"
        }
    }

    // MARK: - 词典

    @State private var newTerm = ""
    @State private var newNote = ""

    private var dictionaryTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("个人词典")
                    .font(.headline)
                Spacer()
                Text("\(dictionary.entries.count) / \(DictionaryStore.maxEntries)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !dictionary.entries.isEmpty {
                    Button("清空") { dictionary.clearAll() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            Toggle("启用词典（出字后自动抽词，并注入提示词纠正识别错误）", isOn: $settings.injectGlossary)

            // 手动添加
            HStack(spacing: 8) {
                TextField("词条（术语 / 人名 / 产品名）", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                TextField("译法 / 备注（可选）", text: $newNote)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    dictionary.add(term: newTerm, note: newNote)
                    newTerm = ""
                    newNote = ""
                }
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if dictionary.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("词典还是空的")
                        .foregroundStyle(.secondary)
                    Text("每次出字后会自动提取术语、人名、产品名入库，也可以在上方手动添加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dictionary.entries) { entry in
                        DictionaryRow(entry: entry, dictionary: dictionary)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    // MARK: - 个性化（风格画像）

    private var personalizeTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("风格画像")
                    .font(.headline)
                Spacer()
                if styleStore.hasProfile {
                    Button("重置") { styleStore.reset() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            Toggle("套用我的风格（自动学习并应用到润色）", isOn: $settings.applyStyle)

            Text("开启后，每次出字会异步学习你的表达习惯（语气、句长、口头禅、标点、中英混用、称呼），润色时贴合，但不改变原意。完全本地、仅自己可见。每次会多一次后台模型调用。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("当前画像（可手动编辑）")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if styleStore.hasProfile || settings.applyStyle {
                TextEditor(text: Binding(
                    get: { styleStore.profile },
                    set: { styleStore.set($0) }
                ))
                .font(.system(size: 13))
                .padding(6)
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

                Text("\(styleStore.profile.count) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("还没有学到你的风格")
                        .foregroundStyle(.secondary)
                    Text("打开上面的开关，正常用几次后，这里就会形成一段你的表达风格画像。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - 历史

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("历史记录")
                    .font(.headline)
                Spacer()
                Text("\(historyManager.entries.count) / 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !historyManager.entries.isEmpty {
                    Button("清空") { historyManager.clearAll() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            if historyManager.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("还没有历史记录")
                        .foregroundStyle(.secondary)
                    Text("你处理过的文字会显示在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(historyManager.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.timeAgo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.model)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.cleanedText, forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc").font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .help("复制")
                                Button(action: { historyManager.remove(entry) }) {
                                    Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("删除")
                            }
                            Text(entry.cleanedText)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .lineLimit(4)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(20)
    }

    // MARK: - 关于

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(.primary)

            Text("PunkType")
                .font(.title)
                .fontWeight(.bold)

            Text("说人话，出成品。")
                .foregroundStyle(.secondary)

            Text("版本 1.3.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Label("\(settings.hotkeyPreset.label) 开始 / 停止录音", systemImage: "keyboard")
                Label("⚡极速 / ✨润色 / 📄格式 三档输出", systemImage: "slider.horizontal.3")
                Label("选中文字 + 快捷键，口述指令处理选区", systemImage: "text.cursor")
                Label("本机识别 + Whisper 云端兜底", systemImage: "waveform")
                Label("个人词典自动学习，纠正识别错误", systemImage: "character.book.closed")
                Label("光标处自动粘贴，并恢复原剪贴板", systemImage: "doc.on.clipboard")
            }
            .font(.callout)

            Spacer()

            VStack(spacing: 4) {
                Toggle("写诊断日志（排查卡顿，记录耗时不记内容）", isOn: $settings.diagnostics)
                    .controlSize(.small)
                    .onChange(of: settings.diagnostics) { _, on in
                        DiagnosticLog.enabled = on
                        if !on { DiagnosticLog.clear() }
                    }
                Text("日志：~/punktype-diagnostics.log")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360)

            Text("开源项目 · github.com/punk2898/PunkType")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func testApiKey() {
        isTesting = true
        testResult = nil

        Task {
            do {
                _ = try await DeepSeekService.cleanup(
                    text: "测试连接",
                    apiKey: settings.apiKey,
                    model: settings.modelPolish,
                    prompt: "回复 OK",
                    endpoint: settings.apiEndpoint
                )
                await MainActor.run {
                    testResult = "✓ 连接成功"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - 词典行（行内可编辑）

private struct DictionaryRow: View {
    @State var entry: DictionaryEntry
    let dictionary: DictionaryStore

    var body: some View {
        HStack {
            TextField("词条", text: $entry.term, onCommit: commit)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))

            TextField("译法 / 备注", text: $entry.note, onCommit: commit)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button(action: { dictionary.remove(entry) }) {
                Image(systemName: "trash").font(.caption).foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(.vertical, 2)
    }

    private func commit() {
        let trimmed = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dictionary.remove(entry)
        } else {
            dictionary.update(entry)
        }
    }
}
