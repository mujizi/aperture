# Aperture

> 让模型输出适配人的信息带宽。

Aperture 在每轮任务结束后读取清理后的用户提问和完整最终回答，由模型生成一个带焦点、决策门和关系视图的注意力场景。它不是任务类型判定系统，也不要求回答套固定章节。

## 工作方式

```text
本地 Session 事件 / 可选 Hooks
            │
            ▼
       Local daemon :4317
            │
        模型 + 默认提示词
            │
            ▼
       AttentionScene v2
            │
      ┌─────┴────────┐
      ▼              ▼
MCP Apps 卡片    macOS 悬浮伴侣
```

- 模型通过 JSON Schema 返回一个 spotlight、可选 decision/blocker gate，以及自由选择的 statement、flow、comparison、metrics 视图。
- 模型输入只有本轮提问、完整最终回答和聚焦度；工具日志与 Aperture 内部事件不会进入模型上下文。
- Review 同时保存注意力场景和由它派生的兼容 Markdown。
- 模型未配置、调用失败、超时或返回空内容时，直接展示明确错误；没有规则模式或原文回退。
- 所有入选信息在一张连续简报中直接显示，无需点击或展开；聚焦度只改变视觉权重，spotlight、真实 gate 和背景信息都不会消失，调整时不重复调用模型。
- 完成结果按实际完成时间保存在历史中；无需页面按钮，按左方向键查看更早结果，按右方向键返回较新结果。
- 处理中只显示光圈动画，不显示加载文字。

## 在这台 Mac 上使用

原生应用安装在 `/Applications/Aperture.app`，运行时不占用 Dock，只保留菜单栏入口。

1. 正常进行任意任务；每轮结束后，悬浮窗会进入处理中并展示压缩结果。
2. 顶栏开关控制监控，下方滑杆控制信息详略，太阳/月亮切换主题，右箭头收起为气泡。
3. 展开态和气泡都可以拖动；点击气泡重新展开。
4. 左右方向键浏览所有历史结果，包括连续任务和同时进行的多个任务。
5. 可选安装 Hooks 以获得额外的生命周期信号；全局 Session Watcher 仍是主要采集通道。

密钥只会发送到 OpenRouter，并以 `0600` 权限保存在 `~/.aperture/.env`。本地服务只监听 `127.0.0.1`。

手动启动：

```bash
open -a Aperture
```

## 开发与验证

```bash
npm install
npm run setup:validator
npm run build
npm test
npm run typecheck
```

重新构建并安装：

```bash
npm run install:plugin
npm run install:mac
```

## 工程目录

```text
src/core/                         事件、AttentionScene 与结果类型
src/server/                       Session Watcher、存储、模型、MCP、HTTP API
src/web/                          单页注意力简报、关系视图、Markdown 兼容与历史浏览
native/ApertureCompanion/         macOS 悬浮窗、气泡与菜单栏应用
plugins/aperture-attention/       可安装插件、Hooks、Skill 与构建产物
scripts/                          构建、演示和安装脚本
```

详细链路见 [架构说明](docs/ARCHITECTURE.md)；当前实际效果、实验回退与 UI/UX 调研见 [当前状态记录](docs/CURRENT_STATE.md)。
