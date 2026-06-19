# 🎙️ PunkType

**简体中文** · [English](README.en.md)

**说人话，出成品。** 在任何输入框里，按下快捷键说话，AI 自动整理成通顺文字，直接打进光标处。

PunkType 是一个 macOS 菜单栏小工具：你说话 → 本机（或 Whisper）转写 → DeepSeek 清理口语、自动排版 → 粘贴到当前输入框。完全免费、开源，自带 API Key，无任何数据上报。

---

## 下载安装

### 方式一：直接下载（推荐）

到 [Releases](https://github.com/punk2898/PunkType/releases) 下载最新的 `PunkType-vX.X.X-macos.zip`，解压后把 `PunkType.app` 拖进「应用程序」。

> **首次打开**：右键点 App → 选「打开」→ 再点「打开」，绕过 Gatekeeper（本包为匿名签名、未经苹果公证）。
> 或在终端执行：`xattr -dr com.apple.quarantine /Applications/PunkType.app`

### 方式二：从源码编译

```bash
git clone https://github.com/punk2898/PunkType.git
cd PunkType
make app      # 编译出 PunkType.app
make install  # 安装到「应用程序」并启动
```

**环境要求**：macOS 14+（Sonoma 及以上）、Xcode 命令行工具（`xcode-select --install`）

---

## 初次配置

1. 到 [platform.deepseek.com](https://platform.deepseek.com) 申请一个 DeepSeek API Key。
2. 启动 PunkType（菜单栏出现波形图标）。
3. 点菜单栏图标 → **设置**，填入你的 API Key。
4. 首次使用按系统提示授予权限：
   - **麦克风** — 录音
   - **语音识别** — 本机转写
   - **辅助功能** — 自动粘贴、读取选中文字（不授予则只能复制到剪贴板）

---

## 怎么用

```
⌥ Space → 说话 → 本机/Whisper 转写 → DeepSeek 整理 → 自动粘贴 ✨
```

- **普通听写**：在任意输入框按 `⌥ Space`，说话，再按一下停止，结果直接打进光标处。
- **选中命令**：先选中一段文字，再按 `⌥ Space`，口述指令（「总结一下」「翻译成英文」「改得更正式」），结果在弹窗中展示，可**复制**或**替换原文**。

---

## 功能

- 🎚️ **三档输出** — ⚡极速（转写直出，零等待）/ ✨润色（清理口语）/ 📄格式（清理 + 自动排版成邮件、汇报、纪要、待办）
- 🎯 **选中命令模式** — 在任意 App 选中文字，按快捷键口述指令，结果弹窗展示，可复制或替换
- 📓 **记事本** — 每次口述自动收进本地记事本，按天归档、自动生成「日报」（⌥⌘N 打开）。完全本地，可按应用排除（微信默认不收录）
- 🧠 **App 感知** — 自动按当前应用调整语气：聊天口语、邮件正式、代码/终端保留术语
- 🎭 **风格画像** — 可选学习你的表达习惯，润色越来越像你本人写的
- 📖 **个人词典** — 每次出字后自动提取术语、人名、产品名（上限 300），回注提示词纠正识别错误，可在设置里增删改
- ☁️ **Whisper 云端兜底** — 可选的 OpenAI 云端转写：格式档自动升级、本机识别失败时自动回落
- 🚀 **快** — 本机语音识别 + DeepSeek Flash；重活（格式/命令）才用 Pro 模型
- 🔒 **隐私** — 你自己的 API Key、你自己的数据，不经过任何中间服务器
- 📋 **粘贴安全** — 自动粘贴到光标处，随后恢复你原来的剪贴板内容
- ⚙️ **可配置** — 快捷键预设、分档模型、三套提示词可编辑、自定义接口地址、开机自启
- 🆓 **开源** — MIT 许可证，代码可审计、可自行编译

---

## 配置说明

### 模型

| 模型 | 提供方 | 特点 |
|------|--------|------|
| DeepSeek V4 Flash | DeepSeek | ⚡ 最快（默认日常档） |
| DeepSeek V4 Pro | DeepSeek | 🧠 最强（格式/命令档） |
| GPT-4o Mini | OpenAI | 💰 便宜 |
| GPT-4o | OpenAI | 🎯 能力强 |
| Claude 3 Haiku | Anthropic | ⚡ 快而聪明 |

### 自定义接口地址

支持任何 OpenAI 兼容接口，改设置里的「接口地址」即可换后端：

- [Groq](https://groq.com) — `https://api.groq.com/openai/v1/chat/completions`
- [OpenRouter](https://openrouter.ai) — `https://openrouter.ai/api/v1/chat/completions`
- 自建/公司内网的任意大模型网关

### 提示词

设置里的「提示词」页可分别编辑**润色 / 格式 / 选中命令**三套提示词，随时恢复默认。

---

## 技术栈

- **Swift 6 + SwiftUI** — 原生 macOS App
- **SFSpeechRecognizer** — 苹果本机语音识别
- **AVFoundation** — 录音
- **Carbon HotKeys** — 全局快捷键
- **MenuBarExtra** — 菜单栏常驻

## 项目结构

```
Sources/
├── App/
│   └── AppDelegate.swift        # 菜单栏、快捷键、三档流水线编排
├── Models/
│   ├── Settings.swift           # UserDefaults 配置 + 默认提示词
│   ├── HistoryManager.swift     # 历史记录
│   └── DictionaryStore.swift    # 个人词典：自动抽词 + 提示词注入
├── Services/
│   ├── SpeechRecognizer.swift   # 本机识别封装 + WAV 录制
│   ├── DeepSeekService.swift    # 聊天接口客户端（OpenAI 兼容）
│   ├── OpenAIService.swift      # Whisper 云端转写
│   ├── SelectionService.swift   # 读取选中文字（AX API + ⌘C 兜底）
│   └── PasteService.swift       # 模拟 ⌘V 粘贴 + 剪贴板保护
└── Views/
    ├── SettingsView.swift       # 设置窗口
    ├── RecordingOverlay.swift   # 录音波形浮窗
    └── CommandResultView.swift  # 选中命令结果弹窗
```

---

## 许可证

[MIT](LICENSE) — 随便用，欢迎贡献。

---

*"最好的工具，是你感觉不到它存在的工具。"*
