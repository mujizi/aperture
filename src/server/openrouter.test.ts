import { afterEach, describe, expect, it, vi } from "vitest";
import { analyzeWithOpenRouter } from "./openrouter";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("OpenRouter Markdown output", () => {
  it("requests and returns Markdown without a structured response format", async () => {
    const answer = `${"完整回答。".repeat(600)}结尾的重要决定。`;
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
      { question: "帮我判断回答里最重要的部分", answer }
    );

    expect(result).toBe("**最重要的结果**：无需处理。");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const body = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    const input = JSON.parse(body.messages[1].content);
    expect(body.response_format).toBeUndefined();
    expect(body.messages[0].content).toContain("聚焦度：62；目标：140 字");
    expect(body.messages[0].content).toContain("Return only the final Chinese Markdown");
    expect(input).toEqual({
      question: "帮我判断回答里最重要的部分",
      answer,
      focus: 62
    });
    expect(input.answer).toContain("结尾的重要决定");
    expect(input.events).toBeUndefined();
  });
});
