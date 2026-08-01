import { afterEach, describe, expect, it, vi } from "vitest";
import { analyzeWithOpenRouter } from "./openrouter";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("OpenRouter attention scene output", () => {
  it("sends the clean question and full answer, then validates a visual scene", async () => {
    const answer = `${"完整回答。".repeat(600)}结尾的重要决定。`;
    const scene = {
      version: 2,
      spotlight: {
        label: "交付结果",
        text: "实现已经完成并通过验证。",
        status: "done",
        highlights: [{ phrase: "通过验证", tone: "verified" }]
      },
      gate: {
        kind: "decision",
        title: "选择高聚焦时是否保留外围光点",
        detail: "该选择只影响视觉密度。",
        options: ["保留光点", "完全隐藏"]
      },
      views: [
        {
          kind: "flow",
          label: "处理链路",
          attention: "supporting",
          status: "done",
          tone: "change",
          steps: [
            { label: "清理输入", detail: "移除工具噪声", tone: "change" },
            { label: "组织场景", detail: "选择合适视图", tone: "verified" }
          ]
        }
      ]
    } as const;
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          choices: [{ message: { content: JSON.stringify(scene) } }]
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

    expect(result).toEqual(scene);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const body = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    const input = JSON.parse(body.messages[1].content);
    expect(body.response_format.type).toBe("json_schema");
    expect(body.response_format.json_schema.name).toBe(
      "aperture_attention_scene"
    );
    expect(body.messages[0].content).toContain("聚焦度：62；目标：140 字");
    expect(body.messages[0].content).toContain("visual attention scene");
    expect(input).toEqual({
      question: "帮我判断回答里最重要的部分",
      answer,
      focus: 62
    });
    expect(input.answer).toContain("结尾的重要决定");
    expect(input.events).toBeUndefined();
  });

  it("removes invalid highlights, duplicate views, and content from an empty gate", async () => {
    const scene = {
      version: 2,
      spotlight: {
        label: "结果",
        text: "代码已经完成。",
        status: "done",
        highlights: [
          { phrase: "代码", tone: "key" },
          { phrase: "代码", tone: "change" },
          { phrase: "并不存在", tone: "risk" }
        ]
      },
      gate: {
        kind: "none",
        title: "模型误填标题",
        detail: "模型误填详情",
        options: ["模型误填选项"]
      },
      views: [
        {
          kind: "statement",
          label: "验证",
          attention: "supporting",
          status: "done",
          tone: "verified",
          text: "测试已经通过。",
          highlights: [
            { phrase: "测试已经通过", tone: "verified" },
            { phrase: "无效短语", tone: "risk" }
          ]
        },
        {
          kind: "statement",
          label: "验证",
          attention: "context",
          status: "none",
          tone: "neutral",
          text: "重复标签。",
          highlights: []
        },
        {
          kind: "statement",
          label: "重复主结论",
          attention: "supporting",
          status: "done",
          tone: "neutral",
          text: "代码已经完成。",
          highlights: []
        }
      ]
    };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            choices: [{ message: { content: JSON.stringify(scene) } }]
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    );

    const result = await analyzeWithOpenRouter(
      {
        apiKey: "test-key-value",
        model: "test/model",
        timeoutMs: 1000
      },
      { question: "结果怎么样", answer: "完整回答" }
    );

    expect(result?.spotlight.highlights).toEqual([
      { phrase: "代码", tone: "key" }
    ]);
    expect(result?.gate).toEqual({
      kind: "none",
      title: "",
      detail: "",
      options: []
    });
    expect(result?.views).toHaveLength(1);
    expect(result?.views[0].kind).toBe("statement");
    if (result?.views[0].kind === "statement") {
      expect(result.views[0].highlights).toEqual([
        { phrase: "测试已经通过", tone: "verified" }
      ]);
    }
  });

  it("limits editorial highlights across the whole scene", async () => {
    const scene = {
      version: 2,
      spotlight: {
        label: "核心结果",
        text: "输入、输出和风险都已梳理。",
        status: "done",
        highlights: [
          { phrase: "输入", tone: "key" },
          { phrase: "输出", tone: "change" },
          { phrase: "风险", tone: "risk" }
        ]
      },
      gate: { kind: "none", title: "", detail: "", options: [] },
      views: [
        {
          kind: "statement",
          label: "实现变化",
          attention: "supporting",
          status: "done",
          tone: "change",
          text: "界面已经更新并完成安装。",
          highlights: [
            { phrase: "已经更新", tone: "change" },
            { phrase: "完成安装", tone: "verified" }
          ]
        },
        {
          kind: "statement",
          label: "验证信息",
          attention: "supporting",
          status: "done",
          tone: "verified",
          text: "测试和健康检查均已通过。",
          highlights: [
            { phrase: "测试", tone: "verified" },
            { phrase: "健康检查", tone: "verified" }
          ]
        },
        {
          kind: "statement",
          label: "背景信息",
          attention: "context",
          status: "none",
          tone: "neutral",
          text: "旧版记录仍然可以读取。",
          highlights: [{ phrase: "仍然可以读取", tone: "key" }]
        }
      ]
    };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            choices: [{ message: { content: JSON.stringify(scene) } }]
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    );

    const result = await analyzeWithOpenRouter(
      {
        apiKey: "test-key-value",
        model: "test/model",
        timeoutMs: 1000
      },
      { question: "改动结果如何", answer: "完整回答" }
    );

    expect(result?.spotlight.highlights).toHaveLength(2);
    const statementHighlights = result?.views.flatMap((view) =>
      view.kind === "statement" ? view.highlights : []
    ) ?? [];
    expect(statementHighlights).toEqual([
      { phrase: "已经更新", tone: "change" },
      { phrase: "测试", tone: "verified" }
    ]);
    expect(
      (result?.spotlight.highlights.length ?? 0) + statementHighlights.length
    ).toBe(4);
  });
});
