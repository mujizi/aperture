# Aperture v0.2.0

[EN](#en) · [CN](#cn)

## CN

Aperture v0.2.0 是首个面向外部试用者的 macOS 预览版。它不是摘要器，而是位于人类输入带宽与大模型输出带宽之间的注意力中间层。Codex 完成一轮工作后，它把完整最终回答重新映射为适合人快速接收的 `AttentionScene`。

注意力转换独立于 Codex 使用的模型。用户可以通过 OpenRouter 选择来自不同模型供应商的模型，包括更便宜、更快的模型，并随时打开或关闭监控。

### 本版包含

- Apple Silicon macOS 悬浮伴侣、菜单栏入口和可收起气泡；
- 自动监听 `~/.codex/sessions` 中的新完成轮次；
- 基于 OpenRouter 的 `AttentionScene v2` 结构化注意力场景；
- spotlight、decision/blocker gate、statement、flow、comparison 和 metrics；
- 本地历史、左右方向键浏览、监控开关、聚焦度、深浅主题、字号和复制；
- 可选的 Codex Hooks、Skill 和本地 MCP 接口；
- 中英双语安装、使用、隐私、限制与设计哲学说明。

### 安装前须知

- 仅支持 Apple Silicon 和 macOS 13+；
- 需要 Node.js 22+、Codex 和 OpenRouter API Key；
- Codex 的模型配置不会自动复用于 Aperture；
- 当前包采用临时签名、未经 Apple 公证，首次打开需要在 macOS 中手动确认；
- 发送给 OpenRouter 的内容包括清理后的本轮问题和 Codex 完整最终回答。

下载 `.dmg` 或 `.zip` 后，将 Aperture 移入 `/Applications`，右键选择“打开”，再在应用设置中配置 OpenRouter。

## EN

Aperture v0.2.0 is the first macOS preview prepared for external testers. It is not a summarizer: it is the attention layer between human input bandwidth and model output bandwidth. After each completed Codex turn, it remaps the complete final answer into an `AttentionScene` that a person can absorb quickly.

The attention pass is independent from the model used by Codex. Through OpenRouter, users can choose models from different upstream providers—including inexpensive, fast models—and turn monitoring on or off at any time.

### Included in this release

- An Apple Silicon macOS floating companion with a menu bar item and collapsible bubble;
- automatic monitoring of newly completed turns in `~/.codex/sessions`;
- OpenRouter-powered structured `AttentionScene v2` output;
- spotlight, decision/blocker gates, statements, flows, comparisons, and metrics;
- local history, arrow-key navigation, monitoring control, focus, themes, font sizing, and copying;
- optional Codex hooks, skill, and local MCP endpoint;
- bilingual documentation covering setup, usage, privacy, limitations, and philosophy.

### Before installing

- Apple Silicon and macOS 13+ are required;
- Node.js 22+, Codex, and an OpenRouter API key are required;
- Codex model configuration is not reused automatically;
- the preview is ad-hoc signed and not Apple-notarized, so macOS requires manual first-launch approval;
- OpenRouter receives the cleaned question and complete Codex final answer for each monitored turn.

Download the `.dmg` or `.zip`, move Aperture to `/Applications`, right-click and choose **Open**, then configure OpenRouter in the app settings.
