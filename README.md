# Aperture

> 让模型输出适配人的信息带宽。

Aperture 在每轮任务结束后读取清理后的用户提问和完整最终回答，再由模型结合聚焦度直接生成一份高信息密度的中文 Markdown。它不是另一套任务判定系统，也不要求模型填写固定字段。

## 工作方式

```text
本地 Session 事件 / 可选 Hooks
            │
            ▼
       Local daemon :4317
            │
     模型 + 默认提示词 + 聚焦度
            │
            ▼
        中文 Markdown
            │
      ┌─────┴────────┐
      ▼              ▼
MCP Apps 卡片    macOS 悬浮伴侣
```

- 模型只返回最终 Markdown，不使用 Structured Outputs 或 JSON Schema。
- 模型输入只有本轮提问、完整最终回答和聚焦度；工具日志与 Aperture 内部事件不会进入模型上下文。
- Review 只保存结果、来源标识、时间和模型调用状态。
- 模型未配置、调用失败、超时或返回空内容时，直接展示明确错误；没有规则模式或原文回退。
- 聚焦度越高，信息筛选越严格、目标篇幅越短；越低则保留更多必要上下文。
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
src/core/                         最小事件与结果类型
src/server/                       Session Watcher、存储、模型、MCP、HTTP API
src/web/                          Markdown 结果与历史浏览
native/ApertureCompanion/         macOS 悬浮窗、气泡与菜单栏应用
plugins/aperture-attention/       可安装插件、Hooks、Skill 与构建产物
scripts/                          构建、演示和安装脚本
```

详细链路见 [架构说明](docs/ARCHITECTURE.md)。
