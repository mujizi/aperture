// @vitest-environment jsdom

import "@testing-library/jest-dom/vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { AttentionScene } from "../core/types";
import { ApertureSceneView } from "./ApertureScene";

afterEach(cleanup);

const sampleScene: AttentionScene = {
  version: 2,
  spotlight: {
    label: "单页简报完成",
    text: "全部已筛选信息现在会在一个连续页面中显示并通过测试。",
    status: "done",
    highlights: [
      { phrase: "一个连续页面", tone: "change" },
      { phrase: "通过测试", tone: "verified" }
    ]
  },
  gate: {
    kind: "decision",
    title: "是否采用自然滚动的单页",
    detail: "推荐允许自然滚动，避免压缩字号。",
    options: ["自然滚动", "强制一屏"]
  },
  views: [
    {
      kind: "flow",
      label: "处理链路",
      attention: "supporting",
      status: "done",
      tone: "change",
      steps: [
        { label: "清理输入", detail: "只保留问题与回答", tone: "change" },
        { label: "关系建模", detail: "选择视觉语法", tone: "verified" }
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
          aspect: "操作",
          left: "点击切换视图",
          right: "全部直接显示",
          change: "better"
        }
      ]
    },
    {
      kind: "metrics",
      label: "验证结果",
      attention: "supporting",
      status: "done",
      tone: "verified",
      items: [
        { label: "测试", value: "31 项通过", tone: "verified" },
        { label: "前端错误", value: "0", tone: "verified" }
      ]
    },
    {
      kind: "statement",
      label: "补充信息",
      attention: "context",
      status: "none",
      tone: "neutral",
      text: "背景信息仍然完整可见。",
      highlights: []
    }
  ]
};

describe("ApertureSceneView", () => {
  it("shows the spotlight, gate, and every visual relationship without interaction", () => {
    const { container } = render(
      <ApertureSceneView scene={sampleScene} focusLevel={0.3} />
    );

    expect(screen.getByText("单页简报完成")).toBeInTheDocument();
    expect(screen.getByText("需要你决定")).toBeInTheDocument();
    expect(screen.getByText("清理输入")).toBeInTheDocument();
    expect(screen.getByText("点击切换视图")).toBeInTheDocument();
    expect(screen.getByText("31 项通过")).toBeInTheDocument();
    expect(screen.getByText("背景信息仍然完整可见。")).toBeInTheDocument();
    expect(screen.queryByRole("navigation")).toBeNull();
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.queryByText("焦点")).toBeNull();
    expect(screen.queryByText("已完成")).toBeNull();
    expect(container.querySelector(".brief-spotlight-meta")).toBeNull();
    expect(screen.getByText("处理链路")).toBeInTheDocument();
    expect(screen.getByText("版本对比")).toBeInTheDocument();
    expect(screen.getByText("验证结果")).toBeInTheDocument();
    expect(container.querySelector("svg")).not.toBeNull();
    expect(screen.getByText("31 项通过").closest(".metric-card")).not.toBeNull();
    expect(container.querySelector(".aperture-brief")?.firstElementChild).toHaveClass(
      "brief-spotlight"
    );
    expect(container.querySelector(".aperture-brief")).toHaveAttribute(
      "data-focus-band",
      "balanced"
    );
  });

  it("uses focus as visual contrast without removing context", () => {
    const { container } = render(
      <ApertureSceneView scene={sampleScene} focusLevel={0.9} />
    );

    expect(container.querySelector(".aperture-brief")).toHaveAttribute(
      "data-focus-band",
      "high"
    );
    expect(screen.getByText("背景信息仍然完整可见。")).toBeInTheDocument();
    expect(screen.getByText("一个连续页面")).toHaveClass("semantic-mark--change");
    expect(screen.getByText("通过测试")).toHaveClass("semantic-mark--verified");
    expect(container.querySelector("mark")).not.toBeNull();
  });

  it("keeps exceptional delivery states visible", () => {
    render(
      <ApertureSceneView
        scene={{
          ...sampleScene,
          spotlight: { ...sampleScene.spotlight, status: "proposed" }
        }}
        focusLevel={0.3}
      />
    );

    expect(screen.getByText("方案")).toBeInTheDocument();
    expect(screen.queryByText("已完成")).toBeNull();
  });

  it("places blockers before the spotlight", () => {
    const blockerScene: AttentionScene = {
      ...sampleScene,
      gate: {
        kind: "blocker",
        title: "模型当前不可用",
        detail: "需要先恢复模型连接。",
        options: []
      }
    };
    const { container } = render(
      <ApertureSceneView scene={blockerScene} focusLevel={0.5} />
    );
    const brief = container.querySelector(".aperture-brief");
    expect(brief?.firstElementChild).toHaveClass("scene-gate--blocker");
  });

  it("localizes scene chrome in English", () => {
    render(
      <ApertureSceneView scene={sampleScene} focusLevel={0.5} language="en" />
    );

    expect(screen.getByText("Decision needed")).toBeInTheDocument();
    expect(screen.getByText("Comparison")).toBeInTheDocument();
    expect(screen.queryByText("需要你决定")).toBeNull();
  });
});
