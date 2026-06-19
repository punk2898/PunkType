import SwiftUI
import Combine
import Carbon

// MARK: - Settings Model

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    // DeepSeek (or any OpenAI-compatible chat endpoint)
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("apiEndpoint") var apiEndpoint: String = "https://api.deepseek.com/chat/completions"

    // Model for command / translate (not a tier) + background term extraction
    @AppStorage("heavyModel") var heavyModel: String = "deepseek-v4-pro"

    // Output tier: fast (raw transcription) / polish (cleanup) / format (cleanup + layout)
    @AppStorage("tier") var tier: String = "polish"

    // MARK: Per-tier configuration (each tier is an editable preset)
    // STT engine per tier: local | apple-fast | whisper
    // Default to Apple 快速识别 (macOS 26 SpeechAnalyzer); auto-falls back to
    // the classic local engine on macOS 25 and earlier.
    @AppStorage("stt_fast")   var sttFast: String = "apple-fast"
    @AppStorage("stt_polish") var sttPolish: String = "apple-fast"
    @AppStorage("stt_format") var sttFormat: String = "apple-fast"
    // Cleanup model per tier (fast tier has no model)
    @AppStorage("model_polish") var modelPolish: String = "deepseek-v4-flash"
    @AppStorage("model_format") var modelFormat: String = "deepseek-v4-pro"
    // Streaming output per tier (type into cursor as it generates)
    @AppStorage("stream_polish") var streamPolish: Bool = true
    @AppStorage("stream_format") var streamFormat: Bool = true

    // Prompts (per tier)
    @AppStorage("systemPrompt") var systemPrompt: String = defaultPrompt
    @AppStorage("formatPrompt") var formatPrompt: String = defaultFormatPrompt
    @AppStorage("commandPrompt") var commandPrompt: String = defaultCommandPrompt

    // Speech recognition
    @AppStorage("language") var language: String = "zh-CN"

    // OpenAI (Whisper cloud transcription)
    @AppStorage("openaiKey") var openaiKey: String = ""
    @AppStorage("openaiModel") var openaiModel: String = "gpt-4o-mini-transcribe"

    // Personal dictionary glossary injection
    @AppStorage("injectGlossary") var injectGlossary: Bool = true

    // Light start/stop cue sounds
    @AppStorage("playSounds") var playSounds: Bool = true

    // App-aware tone: inject the frontmost app's scene into the prompt
    @AppStorage("appAware") var appAware: Bool = true

    // Style profile: learn the user's expression style and apply it to polish
    @AppStorage("applyStyle") var applyStyle: Bool = false

    // Diagnostic timing log (opt-in, for tracing rare hangs)
    @AppStorage("diagnostics") var diagnostics: Bool = false

    // Notebook: passively record every dictation into a local日报-able notebook
    @AppStorage("notebookEnabled") var notebookEnabled: Bool = true

    // MARK: - Per-tier accessors

    func sttEngine(for tier: String) -> String {
        switch tier {
        case "fast":   return sttFast
        case "format": return sttFormat
        default:        return sttPolish
        }
    }

    func model(for tier: String) -> String {
        tier == "format" ? modelFormat : modelPolish
    }

    func stream(for tier: String) -> Bool {
        tier == "format" ? streamFormat : streamPolish
    }

    // Global hotkey preset
    @AppStorage("hotkey") var hotkey: String = "fn"

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasOpenAIKey: Bool {
        !openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Tiers

    static let tiers = ["fast", "polish", "format"]

    static let tierLabels: [String: String] = [
        "fast": "⚡ 极速 — 转写直出，零等待",
        "polish": "✨ 润色 — 清理口语",
        "format": "📄 格式 — 清理 + 自动排版",
    ]

    static let tierShortLabels: [String: String] = [
        "fast": "⚡ 极速",
        "polish": "✨ 润色",
        "format": "📄 格式",
    ]

    // MARK: - Hotkey presets

    struct HotkeyPreset {
        let id: String
        let label: String
        let keyCode: UInt32
        let modifiers: UInt32
    }

    // The "fn" preset is special: it's a single dedicated key handled via an
    // NSEvent flagsChanged monitor (keyCode/modifiers are unused for it).
    static let hotkeyPresets: [HotkeyPreset] = [
        .init(id: "fn", label: "🌐 Fn 键", keyCode: 0, modifiers: 0),
        .init(id: "opt-space", label: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        .init(id: "ctrl-opt-space", label: "⌃⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        .init(id: "opt-cmd-space", label: "⌥⌘ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | cmdKey)),
        .init(id: "shift-opt-space", label: "⇧⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(shiftKey | optionKey)),
    ]

    var hotkeyPreset: HotkeyPreset {
        Self.hotkeyPresets.first { $0.id == hotkey } ?? Self.hotkeyPresets[0]
    }

    // MARK: - Default prompts

    static let defaultPrompt = """
    你是一个语音转文字的整理助手。请把以下语音识别的原始文本整理成通顺的文字：

    规则：
    1. 去掉所有语气词（嗯、啊、那个、这个就是、然后就是、就是说）
    2. 去掉重复、结巴、说了一半又改口的碎片
    3. 理顺语序，让它读起来像一个正常的书面表达
    4. 保留所有专业名词、术语，绝对不要改
    5. 保留说话人的完整意思，不要删减实质内容
    6. 保留说话人的口语风格和语气，不要太书面
    7. 只输出整理后的文本，不要加任何解释
    """

    static let defaultFormatPrompt = """
    你是一个语音转文字的整理排版助手。请把以下语音识别的原始文本整理成可直接使用的成品文字：

    规则：
    1. 先做口语清理：去掉语气词、重复、结巴、改口碎片，理顺语序
    2. 自动判断内容体裁并排版：
       - 邮件：称呼、正文分段、结尾署名位置留空
       - 工作汇报/总结：分点列出，必要时加小标题
       - 会议纪要：按议题分条，单独列出待办事项
       - 待办事项：整理成清单
       - 普通内容：合理分段即可，不要强行加结构
    3. 保留所有专业名词、人名、数字，绝对不要改
    4. 不要编造原文没有的内容
    5. 只输出整理后的文本，不要加任何解释
    """

    static let defaultCommandPrompt = """
    你是一个文字处理助手。用户选中了一段文字，并口述了一个处理指令。
    请严格按指令处理选中的文字，只输出处理结果，不要加任何解释、客套或引号包裹。
    如果指令是翻译，只输出译文；如果指令含糊，按最合理的理解执行。
    """

    static let supportedLanguages: [(code: String, name: String)] = [
        ("zh-CN", "中文（简体）"),
        ("zh-HK", "中文（香港）"),
        ("zh-TW", "中文（台湾）"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("ja-JP", "日本語"),
        ("ko-KR", "한국어"),
    ]

    static let supportedModels = [
        "deepseek-v4-flash",
        "deepseek-v4-pro",
        "gpt-4o-mini",
        "gpt-4o",
        "claude-3-haiku",
    ]

    static let modelLabels: [String: String] = [
        "deepseek-v4-flash": "DeepSeek V4 Flash (最快)",
        "deepseek-v4-pro": "DeepSeek V4 Pro (最强)",
        "gpt-4o-mini": "GPT-4o Mini",
        "gpt-4o": "GPT-4o",
        "claude-3-haiku": "Claude 3 Haiku",
    ]
}
