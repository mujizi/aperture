import { describe, expect, it } from "vitest";
import type { AttentionScene } from "./types";
import { attentionSceneToMarkdown } from "./attention-scene";

describe("attentionSceneToMarkdown", () => {
  it("keeps the gate and converts relationship views into portable Markdown", () => {
    const scene: AttentionScene = {
      version: 2,
      spotlight: {
        label: "结果",
        text: "视觉层已经完成。",
        status: "done",
        highlights: []
      },
      gate: {
        kind: "decision",
        title: "是否保留外围光点",
        detail: "建议保留。",
        options: ["保留", "隐藏"]
      },
      views: [
        {
          kind: "flow",
          label: "处理链路",
          attention: "supporting",
          status: "done",
          tone: "change",
          steps: [
            { label: "输入", detail: "问题与回答", tone: "neutral" },
            { label: "输出", detail: "注意力场景", tone: "change" }
          ]
        },
        {
          kind: "comparison",
          label: "版本对比",
          attention: "supporting",
          status: "done",
          tone: "verified",
          leftLabel: "上一版",
          rightLabel: "当前版",
          rows: [
            {
              aspect: "结构",
              left: "列表",
              right: "关系视图",
              change: "better"
            }
          ]
        }
      ]
    };

    const markdown = attentionSceneToMarkdown(scene);
    expect(markdown).toContain("需要你决定：是否保留外围光点");
    expect(markdown).toContain("1. **输入**：问题与回答");
    expect(markdown).toContain("| 对比项 | 上一版 | 当前版 |");
    expect(markdown).not.toContain("参考：");
  });

  it("uses English structural labels for English reviews", () => {
    const scene: AttentionScene = {
      version: 2,
      spotlight: { label: "Result", text: "The update is ready.", status: "done", highlights: [] },
      gate: {
        kind: "decision",
        title: "Choose a release channel",
        detail: "This controls rollout speed.",
        options: ["Stable", "Preview"]
      },
      views: [{
        kind: "comparison",
        label: "Release options",
        attention: "supporting",
        status: "proposed",
        tone: "change",
        leftLabel: "Stable",
        rightLabel: "Preview",
        rows: [{ aspect: "Speed", left: "Slower", right: "Faster", change: "different" }]
      }]
    };

    const markdown = attentionSceneToMarkdown(scene, "en");
    expect(markdown).toContain("Decision needed: Choose a release channel");
    expect(markdown).toContain("| Comparison | Stable | Preview |");
    expect(markdown).not.toContain("需要你决定");
  });
});
