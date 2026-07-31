import { describe, expect, it } from "vitest";
import type { AgentEvent } from "../core/types";
import { attentionCharacterBudget } from "./openrouter";
import { analyzeEvents } from "./analyzer";

describe("attention focus", () => {
  it("uses a smaller output budget at a higher focus level", () => {
    expect(attentionCharacterBudget(0)).toBe(260);
    expect(attentionCharacterBudget(0.5)).toBe(120);
    expect(attentionCharacterBudget(1)).toBe(45);
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
        payload: { prompt: "给我详细步骤" },
        parentEventId: null
      },
      {
        id: "stop",
        source: "codex",
        runId: "run-focus",
        turnId: "turn-focus",
        timestamp: "2026-07-31T06:01:00.000Z",
        type: "assistant_stop",
        payload: { last_assistant_message: answer },
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
  });
});
