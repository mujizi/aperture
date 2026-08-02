# Aperture v0.2.1

[EN](#en) · [CN](#cn)

## CN

Aperture v0.2.1 是一次 macOS 伴侣体验修复版，重点解决历史浏览时工程标题与正文不一致，以及浮窗图标需要二次点击的问题。

### 本版改进

- 左右方向键浏览历史结果时，顶部工程名会跟随当前展示的记录，不再被后台最新记录覆盖；
- 展开气泡和收起顶部光圈均可单击触发，首次点击不再只用于激活浮窗；
- 新安装或没有历史尺寸设置时，默认展开尺寸调整为 `343 × 726 pt`；
- 保留用户之后手动调整的窗口尺寸。

### 安装前须知

- 仅支持 Apple Silicon 和 macOS 13+；
- 需要 Node.js 22+、Codex 和 OpenRouter API Key；
- 当前包采用临时签名、未经 Apple 公证，首次打开需要在 macOS 中手动确认。

下载 `.dmg` 或 `.zip` 后，将 Aperture 移入 `/Applications`，右键选择“打开”，再在应用设置中配置 OpenRouter。

## EN

Aperture v0.2.1 is a macOS companion maintenance release focused on keeping the project title in sync while browsing history and making the floating controls respond to a single click.

### Improvements

- The project title now follows the history item currently displayed with the left and right arrow keys instead of being overwritten by the newest background review;
- the collapsed bubble and header aperture control now respond on the first click;
- fresh installs, or installs without a saved size, now open at `343 × 726 pt`;
- later user-resized window dimensions remain persisted.

### Before installing

- Apple Silicon and macOS 13+ are required;
- Node.js 22+, Codex, and an OpenRouter API key are required;
- the app is ad-hoc signed and not Apple-notarized, so macOS requires manual approval on first launch.

Download the `.dmg` or `.zip`, move Aperture to `/Applications`, right-click and choose **Open**, then configure OpenRouter in the app settings.
