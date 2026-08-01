import { afterEach, describe, expect, it, vi } from "vitest";
import type { AgentEvent } from "../core/types";
import { attentionCharacterBudget } from "./openrouter";
import { analyzeEvents } from "./analyzer";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("attention focus", () => {
  it("uses a smaller output budget at a higher focus level", () => {
    expect(attentionCharacterBudget(0)).toBe(500);
    expect(attentionCharacterBudget(0.5)).toBe(220);
    expect(attentionCharacterBudget(1)).toBe(90);
  });

  it("surfaces a model error instead of falling back to the source answer", async () => {
    const answer = Array.from(
      { length: 40 },
      (_, index) =>
        `${index + 1}. **步骤 ${index + 1}**：这是需要按顺序执行的一段详细说明。`
    ).join("\n");
    const events: AgentEvent[] = [
      {
        id: "prompt",
        source: "codex",
        runId: "run-focus",
        turnId: "turn-focus",
        timestamp: "2026-07-31T06:00:00.000Z",
        type: "user_prompt",
        payload: { prompt: "给我详细步骤", cwd: "/Users/example/Aperture" },
        parentEventId: null
      },
      {
        id: "stop",
        source: "codex",
        runId: "run-focus",
        turnId: "turn-focus",
        timestamp: "2026-07-31T06:01:00.000Z",
        type: "assistant_stop",
        payload: {
          last_assistant_message: answer,
          cwd: "/Users/example/Aperture"
        },
        parentEventId: "prompt"
      }
    ];

    const result = await analyzeEvents(events, {
      timeoutMs: 10,
      focusLevel: 0.62
    });

    expect(result.analysis.mode).toBe("error");
    expect(result.resultMarkdown).toContain("模型调用失败");
    expect(result.resultMarkdown).toContain("API Key 尚未配置");
    expect(result.resultMarkdown).not.toContain("步骤 1");
    expect(result.projectName).toBe("Aperture");
    expect(result.projectPath).toBe("/Users/example/Aperture");
  });

  it("sends unique questions and the complete final answer without tool events", async () => {
    const answer = `${"正文".repeat(1300)}结尾结论`;
    const events: AgentEvent[] = [
      {
        id: "prompt-1",
        source: "codex",
        runId: "run-input",
        turnId: "turn-input",
        timestamp: "2026-08-01T01:00:00.000Z",
        type: "user_prompt",
        payload: { prompt: "先分析问题" },
        parentEventId: null
      },
      {
        id: "prompt-duplicate",
        source: "codex",
        runId: "run-input",
        turnId: "turn-input",
        timestamp: "2026-08-01T01:00:01.000Z",
        type: "user_prompt",
        payload: { prompt: "先分析问题" },
        parentEventId: null
      },
      {
        id: "prompt-2",
        source: "codex",
        runId: "run-input",
        turnId: "turn-input",
        timestamp: "2026-08-01T01:00:02.000Z",
        type: "user_prompt",
        payload: { prompt: "再给出可执行方案" },
        parentEventId: null
      },
      {
        id: "tool",
        source: "codex",
        runId: "run-input",
        turnId: "turn-input",
        timestamp: "2026-08-01T01:00:03.000Z",
        type: "tool_result",
        payload: {
          tool_name: "exec_command",
          tool_input: "不应进入模型",
          tool_response: "大量工具噪声"
        },
        parentEventId: null
      },
      {
        id: "stop",
        source: "codex",
        runId: "run-input",
        turnId: "turn-input",
        timestamp: "2026-08-01T01:01:00.000Z",
        type: "assistant_stop",
        payload: { last_assistant_message: answer },
        parentEventId: null
      }
    ];
    const scene = {
      version: 2,
      spotlight: {
        label: "聚焦结果",
        text: "聚焦结果",
        status: "done",
        highlights: []
      },
      gate: {
        kind: "none",
        title: "",
        detail: "",
        options: []
      },
      views: [
        {
          kind: "comparison",
          label: "方案对比",
          attention: "supporting",
          status: "done",
          tone: "change",
          leftLabel: "上一版",
          rightLabel: "当前版",
          rows: [
            {
              aspect: "表达",
              left: "普通列表",
              right: "关系视图",
              change: "better"
            }
          ]
        }
      ]
    };
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          choices: [{ message: { content: JSON.stringify(scene) } }]
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await analyzeEvents(events, {
      apiKey: "test-key-value",
      model: "test/model",
      timeoutMs: 1000,
      focusLevel: 0.62,
      customPrompt: "聚焦度：{{focus}}"
    });

    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    const input = JSON.parse(request.messages[1].content);
    expect(input.question).toBe("先分析问题\n\n再给出可执行方案");
    expect(input.answer).toBe(answer);
    expect(input.answer).toContain("结尾结论");
    expect(JSON.stringify(input)).not.toContain("大量工具噪声");
    expect(input.events).toBeUndefined();
    expect(result.attentionScene).toEqual(scene);
    expect(result.resultMarkdown).toContain("**聚焦结果**");
    expect(result.resultMarkdown).toContain("| 对比项 | 上一版 | 当前版 |");
  });
});
