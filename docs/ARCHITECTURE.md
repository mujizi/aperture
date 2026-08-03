# Aperture 架构说明

## 设计原则

1. **聚焦发生在模型选择阶段**：聚焦度映射为提示词的信息压缩率；界面完整展示模型最终选择的语义。
2. **按关系选择视觉语法**：流程、对比、指标和独立陈述各自渲染，不把所有信息压成同一种列表。
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
  attentionScene?: {
    version: 2;
    spotlight: {
      label: string;
      text: string;
      status: "none" | "done" | "partial" | "proposed" | "unverified";
      highlights: Array<{ phrase: string; tone: "key" | "change" | "decision" | "risk" | "verified" }>;
    };
    gate: {
      kind: "none" | "decision" | "blocker";
      title: string;
      detail: string;
      options: string[];
    };
    views: Array<StatementView | FlowView | ComparisonView | MetricsView>;
  };
  attentionDocument?: AttentionDocumentV1; // 仅用于旧历史兼容
  resultMarkdown: string;
  analysis: {
    mode: "model" | "error";
    model: string | null;
    durationMs: number;
    error: string | null;
  };
}
```

`resultMarkdown` 由场景派生，用于复制、旧历史和外部兼容。新界面直接消费 `attentionScene`，不再从 Markdown 粗体或关键词猜测注意力结构。

## 模型链路

```text
清理后的本轮提问 + 完整最终回答
          │
          ▼
默认提示词（选择 spotlight、gate 与关系视图）
          │
          ▼
OpenRouter chat completion
          │
          ├─ JSON Schema 校验通过 ──→ 保存 attentionScene，并派生 resultMarkdown
          └─ 调用异常 ──→ 保存明确错误，mode = error
```

请求使用 JSON Schema 约束最小场景协议。发送给模型的业务输入包括 `question`、`answer`、当前 `focus`、目标压缩率、目标保留率和参考篇幅；不发送工具调用、工具输出、分析生命周期或事件列表。最终回答不按固定字符数截断。提示词只给跨任务目标与关系选择原则，不按任务类型规定固定输出章节。

## 聚焦度

`focusLevel` 持久化在 `~/.aperture/settings.json`，范围为 `0...1`，并直接映射为 `0%...100%` 的目标信息压缩率。调整后会重新分析当前结果：

| 聚焦度 | 模型选择强度 |
|---:|---|
| 0–45 | 保留较多细节、证据与背景 |
| 46–78 | 主动删除低价值背景、实现细节和重复证据 |
| 79–100 | 只保留结论以及理解和行动所必需的信息 |

decision、blocker、重大风险和行动必需信息不受目标压缩率限制。界面不会再按聚焦度机械裁剪 view；模型最终选择的 flow、comparison、metrics 和 statement 都按顺序直接渲染。旧 `AttentionDocument v1` 与纯 Markdown 结果继续使用原渲染器。

## 视觉编码

- 空间与大小表达“焦点 / 上下文”，避免只依赖粗体。
- spotlight 背后的轻量光晕保留 Aperture 的视觉语言，但不承担导航功能。
- 高亮短语必须原样存在于正文；key 与 verified 只增加中性字重，语义颜色细线仅标记 change、decision 和 risk。spotlight 最多 2 个、每个 statement 最多 1 个、全场景最多 4 个。
- `flow` 使用带连接线的步骤轨迹，`comparison` 使用共享维度矩阵，`metrics` 使用数值卡片，`statement` 保留自然语言。
- 路径、链接、命令和工具记录不单独形成视图，除非直接影响用户行动。

## HTTP API

服务只监听 `127.0.0.1:4317`。

| Method | Path | 用途 |
|---|---|---|
| GET | `/api/health` | 健康检查 |
| GET / POST | `/api/config` | 读取非敏感配置或保存模型配置 |
| PATCH | `/api/monitoring` | 开启或暂停采集 |
| PATCH | `/api/focus` | 保存聚焦度并即时更新语义层显示 |
| GET / PUT | `/api/prompt` | 读取或保存提示词 |
| POST | `/api/events` | 追加事件 |
| POST | `/api/analyze` | 为指定轮次生成结果 |
| GET | `/api/review/current` | 当前结果 |
| GET | `/api/reviews` | 历史结果 |
| GET | `/api/stream` | 状态和结果更新流 |
| POST | `/mcp` | MCP Streamable HTTP |

## macOS 伴侣

- `NSPanel` 作为悬浮窗口，折叠后只显示可拖动的透明金色像素猫咪图标。
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
