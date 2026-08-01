# Aperture 架构说明

## 设计原则

1. **适配人的信息带宽**：结果篇幅和筛选强度由聚焦度控制。
2. **模型直接写最终结果**：不要求 JSON、固定字段或分类标签，不做二次拼装。
3. **保留事实边界**：提示词要求不复述问题、不编造事实，并优先保留会影响判断或下一步行动的信息。
4. **失败必须可见**：模型失败直接成为错误结果，不以规则或原回答伪装成功。
5. **历史与当前展示分离**：每轮结果持久化；默认显示最新一页，左右方向键浏览前后结果。

## 数据模型

原始事件保存在 `<data-dir>/events.jsonl`：

```ts
interface AgentEvent {
  id: string;
  source: "codex" | "claude-code" | "cursor" | "manual";
  runId: string;
  turnId: string | null;
  timestamp: string;
  type:
    | "session_start"
    | "user_prompt"
    | "tool_result"
    | "assistant_stop"
    | "analysis_started"
    | "analysis_completed"
    | "feedback";
  payload: Record<string, unknown>;
  parentEventId: string | null;
}
```

结果保存在 `<data-dir>/reviews.jsonl`，只有展示与诊断所需字段：

```ts
interface ReviewSnapshot {
  id: string;
  runId: string;
  turnId: string | null;
  generatedAt: string;
  sourceCompletedAt?: string;
  resultMarkdown: string;
  analysis: {
    mode: "model" | "error";
    model: string | null;
    durationMs: number;
    error: string | null;
  };
}
```

不存在 `summary`、`taskState`、`impact`、`certainty`、`items` 或规则结果。

## 模型链路

```text
清理后的本轮提问 + 完整最终回答 + 聚焦度
          │
          ▼
默认提示词（注入聚焦度与目标字数）
          │
          ▼
OpenRouter chat completion
          │
          ├─ 文本非空 ──→ 直接保存为 resultMarkdown
          └─ 调用异常 ──→ 保存明确错误，mode = error
```

请求不携带 `response_format`、JSON Schema 或 `provider.require_parameters`。发送给模型的业务输入只有 `question`、`answer` 和 `focus`；不发送工具调用、工具输出、分析生命周期或事件列表。最终回答不再按固定字符数截断。响应无需解析业务字段，只读取消息文本并移除模型偶尔添加的外围 Markdown 代码围栏。

## 聚焦度

`focusLevel` 持久化在 `~/.aperture/settings.json`，范围为 `0...1`。越高越聚焦、结果越短：

| 聚焦度 | 目标上限 |
|---:|---:|
| 0–20 | 500 字 |
| 21–40 | 320 字 |
| 41–60 | 220 字 |
| 61–80 | 140 字 |
| 81–100 | 90 字 |

这是软上限。重大阻塞、风险或必须由用户决定的事项优先保留。调整停止 600ms 后，会用新聚焦度重新生成当前一轮结果。

## HTTP API

服务只监听 `127.0.0.1:4317`。

| Method | Path | 用途 |
|---|---|---|
| GET | `/api/health` | 健康检查 |
| GET / POST | `/api/config` | 读取非敏感配置或保存模型配置 |
| PATCH | `/api/monitoring` | 开启或暂停采集 |
| PATCH | `/api/focus` | 保存聚焦度并重新生成当前结果 |
| GET / PUT | `/api/prompt` | 读取或保存提示词 |
| POST | `/api/events` | 追加事件 |
| POST | `/api/analyze` | 为指定轮次生成结果 |
| GET | `/api/review/current` | 当前结果 |
| GET | `/api/reviews` | 历史结果 |
| GET | `/api/stream` | 状态和结果更新流 |
| POST | `/mcp` | MCP Streamable HTTP |

## macOS 伴侣

- `NSPanel` 作为悬浮窗口，折叠后成为可拖动气泡。
- 原生顶栏提供监控、聚焦度、主题和收起控制。
- Web 内容只有等待、处理中和结果三态；处理中只渲染光圈动画。
- 新一轮开始和结果到达时自动展开。
- 结果历史以实际完成时间排序；相同轮次重新生成时替换旧页，避免重复。
- 左方向键翻到更早结果，右方向键回到较新结果，不增加页面控件。

## 采集与故障策略

- Session Watcher 监听本地 session 文件，以单轮结束为处理边界；Hooks 只作为可选低延迟通道。
- Session Watcher 会移除已知的环境、浏览器和附件模板注入，保留并去重同一轮内真实的用户追加要求。
- 工具事件仍可在本地事件存储中用于诊断，但不会进入注意力模型输入。
- 监控关闭期间的轮次不会在重新打开后补处理。
- 服务只监听 loopback；API Key 不会通过读取接口、结果或 MCP 返回。
- Key 保存到 `~/.aperture/.env`，权限为 `0600`。
- 模型区域不可用时短暂熔断，避免连续请求重复等待同一错误。
- Hook 失败不阻断原任务完成。
