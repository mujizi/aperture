import { afterEach, describe, expect, it, vi } from "vitest";
import { analyzeWithOpenRouter } from "./openrouter";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("OpenRouter Markdown output", () => {
  it("requests and returns Markdown without a structured response format", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          choices: [{ message: { content: "**最重要的结果**：无需处理。" } }]
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" }
        }
      )
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await analyzeWithOpenRouter(
      {
        apiKey: "test-key-value",
        model: "test/model",
        timeoutMs: 1000,
        focusLevel: 0.62,
        customPrompt: "聚焦度：{{focus}}；目标：{{targetCharacters}} 字"
      },
      { goal: "测试", events: [] }
    );

    expect(result).toBe("**最重要的结果**：无需处理。");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const body = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(body.response_format).toBeUndefined();
    expect(body.messages[0].content).toContain("聚焦度：62；目标：80 字");
    expect(body.messages[0].content).toContain("Return Markdown only");
  });
});
