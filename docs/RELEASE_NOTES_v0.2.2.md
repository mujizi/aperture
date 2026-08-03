# Aperture v0.2.2

[EN](#en) · [CN](#cn)

## CN

Aperture v0.2.2 更新了 macOS 伴侣的像素猫视觉，并修复未读计数与长历史记录下的稳定性问题。

### 本版改进

- 折叠态使用透明背景的金色像素猫，左眼聚焦镜带有轻量观察动效；
- 展开页同步使用猫咪缩略标志，并更新中英文 README 产品截图；
- 展开时自动定位最新未读结果，翻页会跳到下一条未读并逐条扣减角标；
- 已读结果不会重复扣减，快速翻页会按顺序处理已读请求；
- 历史数据改为流式读取和轻量投影缓存，避免大历史文件导致服务内存溢出。

### 安装前须知

- 仅支持 Apple Silicon 和 macOS 13+；
- 需要 Node.js 22+、Codex 和 OpenRouter API Key；
- 当前包采用临时签名、未经 Apple 公证，首次打开需要在 macOS 中手动确认。

## EN

Aperture v0.2.2 refreshes the macOS companion with its golden pixel cat and fixes unread-count behavior and large-history stability.

### Improvements

- The collapsed companion now uses a transparent golden pixel cat whose left-eye focus lens has a subtle observation animation;
- the expanded header uses the matching cat thumbnail, with refreshed product screenshots in both READMEs;
- expanding opens the newest unread result, while paging advances through unread results and decrements the badge one item at a time;
- revisiting an acknowledged result does not decrement the count again, and rapid paging queues acknowledgements in order;
- event history is streamed and projected into a lightweight cache, preventing large history files from exhausting server memory.

### Before installing

- Apple Silicon and macOS 13+ are required;
- Node.js 22+, Codex, and an OpenRouter API key are required;
- the app is ad-hoc signed and not Apple-notarized, so macOS requires manual approval on first launch.
