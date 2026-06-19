import AppKit

// MARK: - App Context Service
// Resolves the frontmost app (captured at recording start) into a scene hint
// that's injected into the cleanup / format prompt, so tone adapts to where
// you're typing: chat → casual, mail → formal, code → keep terms verbatim.

enum AppContextService {

    struct Context {
        let appName: String
        let bundleID: String
        let hint: String?   // nil = unknown app; just pass the name through
    }

    @MainActor
    static func current(forPID pid: pid_t?) -> Context? {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let name = app.localizedName ?? "应用"
        let bid = app.bundleIdentifier ?? ""
        return Context(appName: name, bundleID: bid, hint: hint(forBundleID: bid.lowercased()))
    }

    private static func hint(forBundleID bid: String) -> String? {
        func has(_ keys: String...) -> Bool { keys.contains { bid.contains($0) } }

        if has("mail", "spark", "outlook", "airmail", "newsletter") {
            return "这是邮件场景：语气正式得体、分段清晰，可保留称呼与结尾署名位置。"
        }
        if has("wechat", "slack", "lark", "feishu", "messages", "ichat", "mobilesms",
               "discord", "telegram", "qq", "whatsapp", "dingtalk") {
            return "这是即时聊天场景：口语化、简短自然，不要书面套话和过度排版。"
        }
        if has("xcode", "vscode", "code", "jetbrains", "intellij", "pycharm",
               "terminal", "iterm", "warp", "sublime", "zed", "cursor") {
            return "这是代码 / 终端场景：保留代码、命令、变量名和技术术语原样，不要翻译或改写专有名词，少加修饰。"
        }
        if has("pages", "word", "notion", "wps", "yuque", "craft", "ulysses") {
            return "这是文档写作场景：书面、条理清晰，适度分段排版。"
        }
        if has("notes", "bear", "obsidian", "logseq") {
            return "这是笔记场景：简洁清晰即可，不必过度正式。"
        }
        return nil
    }
}
