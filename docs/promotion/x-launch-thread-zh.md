# Aperture 中文 X 发布线程

## 第 1 条

大模型输出越来越快，但人的注意力带宽没有变。

我做了 Aperture：夹在人类输入带宽与大模型输出带宽之间的注意力中间层。

它把已完成的 Codex 任务重新组织成：结果、待决策事项、阻塞与证据。开源。🧵

配图：`docs/images/aperture-attention-ui.png`

## 第 2 条

摘要只是把答案变短。

Aperture 试图回答另一个问题：Agent 完成任务后，人应该先看到什么？哪些信息不能消失？

它改变信息的视觉权重，但不删除事实。

配图：`docs/promotion/aperture-workflow.svg.png`

## 第 3 条

它会监听本地已完成的 Codex 回合，任务结束后自动出现在工作区旁边。

看完即可收成一个可拖动的小球，也能前后切换已完成的任务，不必重新翻阅每段对话。

配图：

- `docs/images/aperture-collapsed.png`
- `docs/images/aperture-expanded.jpg`

## 第 4 条

会话捕获、历史与渲染都留在 Mac 本地。

注意力分析时，仅把清理后的问题和最终答案发给你配置的 OpenRouter 模型；不会发送原始工具调用与工具输出。

配图：`docs/promotion/aperture-settings.svg.png`

## 第 5 条

目前是早期预览版：Apple Silicon、macOS 13+、Node.js 22+，需要 OpenRouter Key。

完全开源：https://github.com/mujizi/aperture

当 Agent 完成任务时，你最想先看到什么：结果、决策、阻塞还是证据？
