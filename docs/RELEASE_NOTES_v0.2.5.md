# Aperture v0.2.5

[EN](#en) · [CN](#cn)

## CN

Aperture v0.2.5 修复 macOS 设置页中 OpenRouter API Key 的输入问题。

### 修复

- API Key 在隐藏状态下可直接键入；
- 可从其他应用复制 API Key，并直接粘贴到隐藏状态的输入框；
- 不再需要先点击眼睛切换为明文才能编辑；
- API Key 仍默认隐藏，并避免把它作为已保存的登录密码自动填充。

### 安装前须知

- 仅支持 Apple Silicon 和 macOS 13+；
- 需要 Node.js 22+、Codex 和 OpenRouter API Key；
- 当前包采用临时签名、未经 Apple 公证，首次打开需要在 macOS 中手动确认。

## EN

Aperture v0.2.5 fixes OpenRouter API key entry in macOS settings.

### Fixes

- The API key can be typed while it remains obscured;
- keys copied from other apps can be pasted directly into the obscured field;
- revealing the key is no longer required before editing it;
- the key remains obscured by default without being classified as a saved login password.

### Before installing

- Apple Silicon and macOS 13+ are required;
- Node.js 22+, Codex, and an OpenRouter API key are required;
- the app is ad-hoc signed and not Apple-notarized, so macOS requires manual approval on first launch.
