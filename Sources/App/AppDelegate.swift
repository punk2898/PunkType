import SwiftUI
import AppKit
import Carbon
import AVFoundation
import Speech
@preconcurrency import ApplicationServices

// MARK: - App Entry Point

@main
struct PunkTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var historyManager = HistoryManager.shared
    @ObservedObject private var settings = Settings.shared

    var body: some Scene {
        MenuBarExtra("PunkType", systemImage: appDelegate.isRecording ? "mic.fill.badge.ellipsis" : "mic.fill") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(appDelegate.isRecording ? Color.red : Color.green)
                        .frame(width: 6, height: 6)
                    Text(appDelegate.statusText)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)

                Divider()

                Button(action: { appDelegate.toggleRecording() }) {
                    HStack {
                        Image(systemName: appDelegate.isRecording ? "stop.circle" : "mic.circle")
                        Text(appDelegate.isRecording ? "停止录音" : "开始录音（\(settings.hotkeyPreset.label)）")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

                // Output tier
                Divider()

                Text("输出档位")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)

                ForEach(Settings.tiers, id: \.self) { tier in
                    Button(action: { settings.tier = tier }) {
                        HStack {
                            Image(systemName: settings.tier == tier ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(settings.tier == tier ? .accentColor : .secondary)
                            Text(Settings.tierLabels[tier] ?? tier)
                                .font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                }

                if !appDelegate.lastResult.isEmpty {
                    Divider()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appDelegate.lastResult, forType: .string)
                    }) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("复制上次结果")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }

                // History section
                if !historyManager.entries.isEmpty {
                    Divider()

                    Text("历史")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)

                    ForEach(historyManager.entries.prefix(5)) { entry in
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.cleanedText, forType: .string)
                        }) {
                            HStack {
                                Text(entry.preview)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(entry.timeAgo)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                    }

                    if historyManager.entries.count > 5 {
                        Text("还有 \(historyManager.entries.count - 5) 条 — 在「设置 → 历史」查看")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                    }
                }

                Divider()

                Button(action: { appDelegate.openNotebook() }) {
                    HStack {
                        Image(systemName: "book.closed")
                        Text("记事本…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

                Button(action: { appDelegate.openSettings() }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("设置…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .keyboardShortcut(",", modifiers: [.command])
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

                Divider()

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                        Text("退出")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .keyboardShortcut("q", modifiers: [.command])
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .padding(.bottom, 4)
            }
            .frame(width: 240)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var hotKeyRef: EventHotKeyRef?
    private var notebookHotKeyRef: EventHotKeyRef?
    private var settingsWindow: NSWindow?
    private var notebookWindow: NSWindow?
    private var overlayPanel: NSPanel?

    // Fn-key trigger (handled via NSEvent monitors, not Carbon)
    private var fnMonitors: [Any] = []
    private var fnIsDown = false
    private var otherKeyDuringFn = false

    /// Drives the floating overlay independently of the (localizable) status text.
    enum OverlayPhase { case hidden, listening, processing, done }

    @Published var isRecording = false
    @Published var statusText = "准备就绪"
    @Published var overlayPhase: OverlayPhase = .hidden
    @Published var lastResult: String = ""
    @Published var audioLevel: Float = 0

    /// Frontmost app PID captured when recording started — used to detect
    /// whether the user switched away before the result was ready.
    private var recordingFrontmostPID: pid_t?

    /// App scene captured at recording start → injected into the prompt so the
    /// cleanup tone matches where you're typing (chat/mail/code/…).
    private var recordingAppContext: AppContextService.Context?

    /// When the user stopped recording — origin for diagnostic stage timings.
    private var sttStopTime: Date?
    private func ms(since t: Date?) -> Int {
        guard let t else { return -1 }
        return Int(Date().timeIntervalSince(t) * 1000)
    }

    /// Selected text captured when recording started → command mode
    private var commandTarget: String?

    let settings = Settings.shared
    private(set) var speechRecognizer: any SpeechTranscribing = SpeechRecognizer(locale: Settings.shared.language)
    private var activeEngineKey = ""

    /// (Re)build the speech engine for the active tier's STT choice.
    /// "apple-fast" → SpeechAnalyzer; "local"/"whisper" → SFSpeech (which also
    /// writes the WAV that the Whisper upload path needs).
    private func ensureRecognizer() {
        let engine = settings.sttEngine(for: settings.tier)
        let useModern = engine == "apple-fast"
        let key = "\(useModern)|\(settings.language)"
        guard key != activeEngineKey else { return }
        activeEngineKey = key
        if useModern, #available(macOS 26.0, *) {
            speechRecognizer = ModernSpeechRecognizer(localeIdentifier: settings.language)
            print("[PunkType] 🎙️ Engine: SpeechAnalyzer (\(settings.language))")
        } else {
            speechRecognizer = SpeechRecognizer(locale: settings.language)
            print("[PunkType] 🎙️ Engine: SFSpeechRecognizer (\(settings.language))")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.enabled = settings.diagnostics
        setupHotkeyHandler()
        registerHotkey()

        // On launch, backfill daily reports for past days that don't have one
        // yet (so yesterday's report is ready the next morning). Delayed so it
        // doesn't slow startup; never touches today (still in progress).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.autoGenerateMissingReports()
        }

        // Trigger system Accessibility prompt once (silent if already granted)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Global Hotkey

    private func setupHotkeyHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let target = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let ptr = userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                let id = hkID.id
                Task { @MainActor in
                    if id == 2 { delegate.openNotebook() } else { delegate.toggleRecording() }
                }
                return noErr
            },
            1,
            &eventType,
            target,
            nil
        )

        // Notebook hotkey: ⌥⌘N (fixed, independent of the main trigger).
        let nbID = EventHotKeyID(signature: 0x70756E6B, id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey),
                            nbID, GetApplicationEventTarget(), 0, &notebookHotKeyRef)
    }

    /// (Re)register the global hotkey from the current settings preset.
    func registerHotkey() {
        // Tear down whichever mechanism is currently active.
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        removeFnMonitor()

        // Fn key uses a flagsChanged monitor (Carbon can't bind a lone Fn key).
        if settings.hotkey == "fn" {
            installFnMonitor()
            print("[PunkType] ⌨️ Hotkey: 🌐 Fn key")
            return
        }

        let preset = settings.hotkeyPreset
        let hotKeyID = EventHotKeyID(signature: 0x70756E6B, id: 1)
        RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        print("[PunkType] ⌨️ Hotkey registered: \(preset.label)")
    }

    // MARK: - Fn-key monitor

    /// A tap of the Fn (🌐) key toggles recording. We trigger on Fn *release*,
    /// and only if no other key was pressed while Fn was held — so Fn+F-key
    /// combos and Globe shortcuts don't accidentally fire it.
    private func installFnMonitor() {
        fnIsDown = false
        otherKeyDuringFn = false

        let addFlags: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleFnFlags(event) }
        }
        let addKey: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.noteKeyDuringFn() }
        }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: addFlags) {
            fnMonitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in addFlags(e); return e }) {
            fnMonitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: addKey) {
            fnMonitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { e in addKey(e); return e }) {
            fnMonitors.append(m)
        }
    }

    private func removeFnMonitor() {
        for m in fnMonitors { NSEvent.removeMonitor(m) }
        fnMonitors.removeAll()
        fnIsDown = false
        otherKeyDuringFn = false
    }

    private func handleFnFlags(_ event: NSEvent) {
        let isFn = event.modifierFlags.contains(.function)
        if isFn && !fnIsDown {
            fnIsDown = true
            otherKeyDuringFn = false
        } else if !isFn && fnIsDown {
            fnIsDown = false
            if !otherKeyDuringFn {
                toggleRecording()
            }
        }
    }

    private func noteKeyDuringFn() {
        if fnIsDown { otherKeyDuringFn = true }
    }

    // MARK: - Overlay Window

    private func showOverlay() {
        if overlayPanel == nil {
            let overlay = RecordingOverlay(appDelegate: self)
            let hosting = NSHostingController(rootView: overlay)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hosting
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.hidesOnDeactivate = false

            overlayPanel = panel
        }

        // Bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = overlayPanel!.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.minY + 60
            overlayPanel?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        overlayPanel?.orderFront(nil)
    }

    private func hideOverlay(after seconds: Double = 1.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.overlayPanel?.orderOut(nil)
        }
    }

    // MARK: - Command Result Panel

    private var commandPanel: NSPanel?

    /// Command-mode result → panel where paste means "替换原文".
    private func showCommandResult(instruction: String, result: String) {
        showResultPanel(
            title: "处理结果",
            subtitle: instruction.isEmpty ? "" : "指令：\(instruction)",
            result: result,
            pasteLabel: "替换原文"
        )
    }

    /// Show a text result in a floating, non-activating panel so the host app
    /// keeps focus (so the paste button can land in it after you click back).
    private func showResultPanel(title: String, subtitle: String, result: String, pasteLabel: String) {
        closeCommandResult()

        let view = CommandResultView(
            title: title,
            subtitle: subtitle,
            result: result,
            pasteLabel: pasteLabel,
            onPaste: { [weak self] in
                self?.closeCommandResult()
                // Give focus a beat to settle back on the host field, then paste
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    _ = PasteService.copyAndPaste(result)
                }
            },
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
                self?.statusText = "已复制"
                self?.closeCommandResult()
            },
            onClose: { [weak self] in
                self?.closeCommandResult()
            }
        )

        let panelSize = NSSize(width: 460, height: 380)
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.setContentSize(panelSize)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false

        // Position: centered, slightly below screen center so it's easy to read
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY - panelSize.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        commandPanel = panel
    }

    private func closeCommandResult() {
        commandPanel?.orderOut(nil)
        commandPanel = nil
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        // 极速档不走 LLM，无 key 也能用；其余档位需要 DeepSeek key
        if settings.tier != "fast" && !settings.isConfigured {
            showAlert(message: "Please configure your DeepSeek API Key in Settings first.")
            return
        }

        ensureRecognizer()

        // Remember where we started so we can tell if the user switches away,
        // and capture the app scene (used for tone adaptation + notebook source).
        recordingFrontmostPID = FocusService.frontmostPID()
        recordingAppContext = AppContextService.current(forPID: recordingFrontmostPID)

        // Command mode: text selected in the host app → speak an instruction
        commandTarget = settings.isConfigured ? SelectionService.selectedText() : nil

        isRecording = true
        overlayPhase = .listening
        if let target = commandTarget {
            let preview = String(target.prefix(10))
            statusText = "已选中「\(preview)\(target.count > 10 ? "…" : "")」说出指令"
        } else {
            statusText = "聆听中…"
        }
        showOverlay()

        // Wire up live audio level for waveform
        speechRecognizer.onAudioLevel = { @Sendable [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        // Start cue — play before the engine starts so the mic won't capture it.
        if settings.playSounds { SoundService.playStart() }

        do {
            try speechRecognizer.startRecording()
        } catch {
            isRecording = false
            overlayPhase = .hidden
            statusText = "出错了"
            overlayPanel?.orderOut(nil)
            showAlert(message: error.localizedDescription)
        }
    }

    private func stopRecording() {
        isRecording = false
        overlayPhase = .processing
        statusText = "AI 处理中…"
        sttStopTime = Date()
        DiagnosticLog.log("STOP — tier=\(settings.tier) app=\(recordingAppContext?.appName ?? "?")")

        // Stop cue — the engine is stopped synchronously inside stopRecording
        // below, and the system sound has enough latency that it isn't captured.
        if settings.playSounds { SoundService.playStop() }

        speechRecognizer.stopRecording { @Sendable [weak self] rawText in
            Task { @MainActor in
                guard let self else { return }
                await self.handleTranscription(localText: rawText)
            }
        }
    }

    // MARK: - STT result → Whisper upgrade/fallback → process

    private func handleTranscription(localText: String) async {
        var text = localText
        DiagnosticLog.log("STT delivered +\(ms(since: sttStopTime))ms (\(localText.count)字)")

        // 当前档选了 Whisper 时优先用 Whisper；本机识别为空时也兜底 Whisper
        let preferWhisper = settings.sttEngine(for: settings.tier) == "whisper"
        if settings.hasOpenAIKey,
           preferWhisper || text.isEmpty,
           let audioURL = speechRecognizer.lastAudioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            statusText = "转写中…"
            do {
                let whisperText = try await OpenAIService.transcribe(
                    audioURL: audioURL,
                    apiKey: settings.openaiKey,
                    model: settings.openaiModel
                )
                if !whisperText.isEmpty {
                    text = whisperText
                }
            } catch {
                print("[PunkType] ⚠️ Whisper failed, using local text: \(error.localizedDescription)")
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "未检测到语音"
            overlayPhase = .hidden
            overlayPanel?.orderOut(nil)
            commandTarget = nil
            return
        }

        await processAndPaste(trimmed)
    }

    // MARK: - Prompt building (glossary + app-aware tone)

    /// Build the system prompt for a cleanup tier: base prompt + dictionary
    /// glossary + the captured app scene hint (when App-aware is on).
    private func buildPrompt(for tier: String, dictionary: DictionaryStore) -> String {
        var prompt = (tier == "format") ? settings.formatPrompt : settings.systemPrompt
        if settings.injectGlossary, let glossary = dictionary.correctionGlossary {
            prompt += glossary
        }
        if settings.appAware, let ctx = recordingAppContext {
            prompt += "\n\n【当前场景】用户正在「\(ctx.appName)」中输入。"
                + (ctx.hint ?? "请贴合该应用常见的输入场景自然整理。")
        }
        // Personal style — polish only (formatted emails/reports keep their own tone).
        if settings.applyStyle, tier != "format", let style = StyleProfileStore.shared.promptBlock {
            prompt += style
        }
        return prompt
    }

    // MARK: - Tier pipeline + Paste

    private func processAndPaste(_ rawText: String) async {
        statusText = "AI 处理中…"
        let dictionary = DictionaryStore.shared
        let target = commandTarget
        commandTarget = nil

        var output = rawText
        var usedModel = "raw"

        // Command mode is handled separately: the result is shown in a panel
        // (with 复制 / 替换原文 / 关闭) instead of being blindly pasted, because
        // the selection is often in a read-only place.
        if let target {
            var prompt = settings.commandPrompt
            if settings.injectGlossary, let glossary = dictionary.commandGlossary {
                prompt += glossary
            }
            do {
                let result = try await DeepSeekService.command(
                    instruction: rawText,
                    selectedText: target,
                    apiKey: settings.apiKey,
                    model: settings.heavyModel,
                    prompt: prompt,
                    endpoint: settings.apiEndpoint
                )
                self.lastResult = result
                overlayPhase = .hidden
                overlayPanel?.orderOut(nil)
                statusText = "准备就绪"
                showCommandResult(instruction: rawText, result: result)
                HistoryManager.shared.add(
                    cleanedText: result,
                    rawText: "指令：\(rawText)",
                    model: settings.heavyModel
                )
                if settings.injectGlossary, settings.isConfigured {
                    extractTermsInBackground(from: result)
                }
            } catch {
                print("[PunkType] ❌ Command failed: \(error.localizedDescription)")
                overlayPhase = .hidden
                statusText = "命令失败"
                hideOverlay(after: 1.0)
            }
            return
        }

        // Streaming path (per-tier): type the cleaned text into the cursor as it
        // streams, for lower perceived latency. Only when there's a confident
        // paste target up front; otherwise fall through to the normal path.
        if settings.stream(for: settings.tier), settings.tier != "fast", settings.isConfigured {
            let switchedAway = recordingFrontmostPID == nil
                || FocusService.frontmostPID() != recordingFrontmostPID
            let canType = !switchedAway && FocusService.editableFocusState() != .nonEditable
            if canType {
                if await streamAndType(rawText, dictionary: dictionary) { return }
            } else {
                DiagnosticLog.log("→ 走非流式（switchedAway=\(switchedAway), nonEditable=\(!switchedAway)）")
            }
        }

        // Normal dictation: 极速 / 润色 / 格式 → auto-paste at cursor
        do {
            switch settings.tier {
            case "fast":
                break // raw transcription as-is
            case "format":
                let prompt = buildPrompt(for: "format", dictionary: dictionary)
                let m = settings.model(for: "format")
                output = try await DeepSeekService.cleanup(
                    text: rawText,
                    apiKey: settings.apiKey,
                    model: m,
                    prompt: prompt,
                    endpoint: settings.apiEndpoint,
                    maxTokens: 2048,
                    timeout: 30
                )
                usedModel = m
            default: // polish
                let prompt = buildPrompt(for: "polish", dictionary: dictionary)
                let m = settings.model(for: "polish")
                output = try await DeepSeekService.cleanup(
                    text: rawText,
                    apiKey: settings.apiKey,
                    model: m,
                    prompt: prompt,
                    endpoint: settings.apiEndpoint
                )
                usedModel = m
            }
        } catch {
            // 清理失败 → 退回原始转写
            print("[PunkType] ⚠️ Cleanup failed, pasting raw: \(error.localizedDescription)")
            output = rawText
            usedModel = "raw (fallback)"
        }
        DiagnosticLog.log("非流式 完成 +\(ms(since: sttStopTime))ms (\(output.count)字)")

        self.lastResult = output

        // Save to history regardless of where the text lands
        HistoryManager.shared.add(
            cleanedText: output,
            rawText: rawText,
            model: usedModel
        )
        // 异步抽词入库 + 风格学习（不阻塞出字）
        if settings.injectGlossary, settings.isConfigured {
            extractTermsInBackground(from: output)
        }
        updateStyleInBackground(from: output)
        recordToNotebook(output)

        // Decide: paste at the cursor, or show the result in a panel?
        // Pop the panel only when we're confident there's nowhere to paste:
        //   • the user switched to a different app/desktop, OR
        //   • the same app reports focus on a clearly non-text control.
        // Otherwise (editable, or can't tell) → paste.
        let switchedAway = recordingFrontmostPID == nil
            || FocusService.frontmostPID() != recordingFrontmostPID
        let noTextHere = FocusService.editableFocusState() == .nonEditable
        guard !switchedAway && !noTextHere else {
            print("[PunkType] 📋 No paste target (switchedAway=\(switchedAway), noTextHere=\(noTextHere)) — showing panel")
            overlayPhase = .hidden
            overlayPanel?.orderOut(nil)
            statusText = "准备就绪"
            showResultPanel(
                title: "转写结果（未找到输入框）",
                subtitle: "点回输入框后可「插入到光标」，或直接复制",
                result: output,
                pasteLabel: "插入到光标"
            )
            return
        }

        let pasteStatus = PasteService.copyAndPaste(output)
        print("[PunkType] 📋 \(pasteStatus): \(output.prefix(50))...")
        self.statusText = pasteStatus
        self.overlayPhase = .done

        // Auto-dismiss overlay
        hideOverlay(after: 1.5)

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if self.overlayPhase == .done {
            self.statusText = "准备就绪"
            self.overlayPhase = .hidden
        }
    }

    /// Stream the cleaned text and type it at the cursor as tokens arrive.
    /// Returns true if it handled output; false if it should fall back to the
    /// normal (non-streaming) path (e.g. failed before any token).
    private func streamAndType(_ rawText: String, dictionary: DictionaryStore) async -> Bool {
        let isFormat = settings.tier == "format"
        let prompt = buildPrompt(for: settings.tier, dictionary: dictionary)
        let model = settings.model(for: settings.tier)

        statusText = "AI 处理中…"
        var typed = ""
        do {
            let stream = DeepSeekService.streamCleanup(
                text: rawText,
                apiKey: settings.apiKey,
                model: model,
                prompt: prompt,
                endpoint: settings.apiEndpoint,
                maxTokens: isFormat ? 2048 : 1024
            )
            for try await delta in stream {
                if typed.isEmpty {
                    // First token arrived — clear the overlay so typing is visible
                    overlayPhase = .hidden
                    overlayPanel?.orderOut(nil)
                    DiagnosticLog.log("流式 首字 +\(ms(since: sttStopTime))ms")
                }
                typed += delta
                TypeService.insert(delta)
            }
            DiagnosticLog.log("流式 完成 +\(ms(since: sttStopTime))ms (\(typed.count)字)")
        } catch {
            print("[PunkType] ⚠️ Streaming failed after \(typed.count) chars: \(error.localizedDescription)")
            DiagnosticLog.log("流式 出错 +\(ms(since: sttStopTime))ms (已出\(typed.count)字): \(error.localizedDescription)")
            if typed.isEmpty { return false } // nothing typed → safe to fall back
        }

        guard !typed.isEmpty else { return false }

        let output = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastResult = output
        self.statusText = "已粘贴 ✓"
        HistoryManager.shared.add(cleanedText: output, rawText: rawText, model: model)
        if settings.injectGlossary {
            extractTermsInBackground(from: output)
        }
        updateStyleInBackground(from: output)
        recordToNotebook(output)

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if self.statusText == "已粘贴 ✓" { self.statusText = "准备就绪" }
        return true
    }

    // MARK: - Dictionary post-processing

    private func extractTermsInBackground(from text: String) {
        let apiKey = settings.apiKey
        let model = settings.modelPolish // background extraction uses the light model
        let endpoint = settings.apiEndpoint
        Task {
            do {
                let terms = try await DeepSeekService.extractTerms(
                    from: text,
                    apiKey: apiKey,
                    model: model,
                    endpoint: endpoint
                )
                guard !terms.isEmpty else { return }
                await MainActor.run {
                    DictionaryStore.shared.merge(terms: terms)
                }
            } catch {
                print("[PunkType] ⚠️ Term extraction failed: \(error.localizedDescription)")
            }
        }
    }

    /// Incrementally learn the user's expression style from an output sample.
    /// Skips trivial outputs and only runs when "套用我的风格" is on.
    private func updateStyleInBackground(from text: String) {
        guard settings.applyStyle, settings.isConfigured,
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12 else { return }
        let apiKey = settings.apiKey
        let model = settings.modelPolish
        let endpoint = settings.apiEndpoint
        let current = StyleProfileStore.shared.profile
        Task {
            do {
                let updated = try await DeepSeekService.updateStyleProfile(
                    current: current,
                    sample: text,
                    apiKey: apiKey,
                    model: model,
                    endpoint: endpoint
                )
                guard !updated.isEmpty else { return }
                await MainActor.run {
                    StyleProfileStore.shared.set(updated)
                }
            } catch {
                print("[PunkType] ⚠️ Style update failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Notebook

    /// Record a dictation output into the notebook (unless disabled / app excluded).
    private func recordToNotebook(_ text: String) {
        guard settings.notebookEnabled else { return }
        NotebookStore.shared.record(
            text: text,
            app: recordingAppContext?.appName ?? "未知应用",
            bundleID: recordingAppContext?.bundleID ?? "",
            tier: settings.tier
        )
    }

    /// Generate (or regenerate) the daily report for a day, then call back.
    func generateDailyReport(day: String, entriesText: String, completion: @escaping @MainActor () -> Void) {
        let apiKey = settings.apiKey
        let model = settings.modelPolish
        let endpoint = settings.apiEndpoint
        guard settings.isConfigured else { completion(); return }
        Task {
            defer { Task { @MainActor in completion() } }
            do {
                let report = try await DeepSeekService.dailySummary(
                    entriesText: entriesText, apiKey: apiKey, model: model, endpoint: endpoint
                )
                await MainActor.run {
                    NotebookStore.shared.setSummary(day: day, DailySummary(
                        title: report.title, body: report.body, generatedAt: Date()
                    ))
                }
            } catch {
                print("[PunkType] ⚠️ Daily report failed: \(error.localizedDescription)")
            }
        }
    }

    /// Generate reports for past days (not today) that have entries but no
    /// summary yet. Capped to the most recent few to avoid an API burst.
    func autoGenerateMissingReports() {
        guard settings.notebookEnabled, settings.isConfigured else { return }
        let store = NotebookStore.shared
        let today = NotebookStore.dayKey(Date())
        let candidates = store.availableDates
            .filter { $0 != today }
            .prefix(7)
            .filter { day in
                guard let note = store.loadDay(day) else { return false }
                return note.summary == nil && !note.entries.isEmpty
            }
        guard !candidates.isEmpty else { return }

        let apiKey = settings.apiKey, model = settings.modelPolish, endpoint = settings.apiEndpoint
        Task {
            for day in candidates {
                guard let note = store.loadDay(day) else { continue }
                let text = note.entries
                    .map { "\($0.timeLabel) [\($0.sourceApp)] \($0.text)" }
                    .joined(separator: "\n")
                do {
                    let report = try await DeepSeekService.dailySummary(
                        entriesText: text, apiKey: apiKey, model: model, endpoint: endpoint
                    )
                    await MainActor.run {
                        store.setSummary(day: day, DailySummary(
                            title: report.title, body: report.body, generatedAt: Date()
                        ))
                    }
                } catch {
                    print("[PunkType] ⚠️ Auto report failed for \(day): \(error.localizedDescription)")
                }
            }
        }
    }

    func openNotebook() {
        if let window = notebookWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = NotebookView(appDelegate: self)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "PunkType 记事本"
        window.setContentSize(NSSize(width: 760, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        notebookWindow = window
    }

    // MARK: - Settings Window

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView()
            .environmentObject(self)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "PunkType Settings"
        window.setContentSize(NSSize(width: 520, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    // MARK: - Alerts

    func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "PunkType"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

}
