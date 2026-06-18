# PunkType 开放架构 / Roadmap

> 本文固化「开放方向」的设计思路与路线。核心判断：作为开源项目，PunkType 的根本优势不是再堆一个功能，而是**让别人能往里加东西**。我们已有的「全可自定义」（档位顺序、提示词、模型、词典、App 规则）本质上**全是配置数据**，把它做成可分享、可扩展，就是闭源竞品（Typeless / superwhisper 等）结构上学不来的护城河。

---

## 一、三层开放架构（总纲）

后续所有功能都往这张图里挂，不做零散功能，而是搭一个开放骨架：

```
① 输入层    识别引擎（本机 / Apple 快速 / Whisper）        —— 已可配
② 处理层    提示词 / 模型 / 档位（= 模式包）               —— 已可配；「配置包」让它可分享
③ 后处理层  出字之后的额外动作（Hook）                     —— 新增
             └─ 官方 Hook #1：记事本（自动分类归档）
             └─ 以后：翻译并存档 / 推送到 Obsidian / 调用快捷指令 / …
```

- **配置包**装的是 ②（并可声明启用哪些 ③）。
- **记事本**是 ③ 的第一个官方实现。
- 任何「出字后再做点啥」都是 ③ 上的一个新 Hook：官方先做，成熟后再开放第三方。

---

## 二、模式包（配置包，②层的分享）

### 是什么

一个「模式 / 包」= 一坨**纯数据，没有代码**（因此零安全风险、零运行时）。例如不同的提示词人格：正经、深思熟虑、调情、诡辩……差异全在提示词。

### 包的结构（草案）

```jsonc
{
  "id": "sophist-mode",
  "name": "诡辩模式",
  "icon": "🗣️",
  "version": "1.0",
  "author": "punk2898",
  "tier": {
    "prompt": "……核心提示词……",
    "model": "deepseek-v4-pro",
    "sttEngine": "apple-fast",
    "streaming": true
  },
  "appRules": [ /* 可选：哪些 App 自动启用 */ ],
  "dictionary": [ /* 可选：专属词条 */ ],
  "hooks": [ /* 可选：启用哪些后处理 */ ]
}
```

### 导出 / 导入

- 导出：把当前一档（或全部设置）打成一个 `.json`。
- 导入：读进来变成一个可选档位 / 一套配置。
- 这正是 [Espanso 包](https://espanso.org/docs/packages/basics/) 的玩法——可分享、可积累、可审计。

---

## 三、分发策略

原则：**官方包优先，第三方靠后；商城太早，先用 GitHub。**

- **官方优先**：早期由官方精选几个高质量模式包，质量与安全可控，等生态起来再开放第三方贡献。
- **GitHub 即轻量商城**（零后端）：仓库里放
  - `packs/` 目录存放各模式包 `.json`
  - 一个 `packs/index.json` 清单（列出官方包：名称、描述、文件名、版本）
  - App 内：拉取清单 → 列表展示 → 一键导入
- 等真的有规模了，再升级成网页商城不迟。Espanso 自己就是 GitHub Releases 起家。

---

## 四、后处理 Hook 层（③）

「出字完成后，能不能再多做一步处理？」——这就是 Hook。

- 定义一个**输出后的管道阶段**：拿到最终文本 → 依次跑启用的 Hook。
- Hook 不阻塞出字（异步），跟现有的「异步抽词 / 风格学习」同一套路。
- 官方先做内置 Hook；远期可开放「调用用户自己的脚本 / macOS 快捷指令」给极客（opt-in，安全边界清晰）。

---

## 五、记事本（官方 Hook #1）

### 概念

把你**日常口述的内容**，顺手收进一个**私密、本地**的记事本：自动分类打标签、可编辑、可搜索、可导出。它是日常打字的**副产品**——你本来就在到处语音输入，零额外动作就攒出一份个人记录。

### 差异点（对标已有产品）

| 产品 | 形态 |
|---|---|
| [AudioPen](https://www.audiopen.ai/) | 专门去录 → 润色成笔记 |
| [Voicenotes](https://nubiapage.com/voicenotes-review-2026-ai-app-pricing-login-user-experience-and-faqs/) | 语音知识库 + 可搜索 + 接 Obsidian/Notion |
| AudioNotes / TalkNotes | 转写 + 分类 + 模板归档 |

它们都是**「专门去记笔记」的独立 App**。PunkType 的不同：**记录是日常输入的副产品**，被动收录、完全本地私密——这个角度上面竞品都没有。

### 架构契合（不是新 App，是现有东西的进化）

- 已有 `HistoryManager`，**每次出字都已存储**。
- 记事本 = HistoryManager + ① 异步 AI 分类打标签 + ② 独立窗口（快捷键唤起）可看 / 编辑 / 搜索 / 导出。

### 待定取舍（需拍板）

- **收录范围**：被动收录所有口述？还是只收录手动标记的几条？（影响形态与隐私观感）
- **分类粒度**：自动标签 vs 自定义分类。
- **存储**：纯本地（Application Support）默认；是否提供导出到 Obsidian/Markdown。

---

## 六、路线图 / 优先级

1. **配置包导出 / 导入（②的地基）** — 最小、最稳；做完「可分享」即成立，官方放几个示范模式包。
2. **后处理 Hook 机制 + 记事本（③的第一个 Hook）** — 更大、最差异化；等骨架想清楚再上，避免做成孤立功能。
3. **开放第三方**（社区包贡献规范、用户脚本/快捷指令 Hook） — 最后，等前两步验证后再说。

---

## 七、参考产品

- [Espanso](https://github.com/espanso/espanso) + [包系统](https://espanso.org/docs/packages/basics/) —— 声明式「包 + 社区 Hub」的最佳范本（数据非代码）
- [prompts.chat](https://github.com/f/prompts.chat) —— 社区提示词库（14 万 star，纯 markdown/CSV，可作 MCP server）
- [AudioPen](https://www.audiopen.ai/) / [Voicenotes](https://nubiapage.com/voicenotes-review-2026-ai-app-pricing-login-user-experience-and-faqs/) / AudioNotes / TalkNotes —— 记事本方向的对标
- Raycast 扩展 / Obsidian 插件 —— 代码插件运行时（**早期刻意不做**：成本高、安全/维护重）
