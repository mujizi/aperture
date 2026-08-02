// @vitest-environment jsdom

import "@testing-library/jest-dom/vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { AttentionDocument } from "../core/types";
import { AttentionDocumentView } from "./AttentionDocument";

afterEach(cleanup);

const sampleDocument: AttentionDocument = {
  version: 1,
  blocks: [
    {
      content: "代码已经修改并通过测试。",
      attention: "essential",
      role: "outcome",
      status: "done"
    },
    {
      content: "模型输入只包含问题和最终回答。",
      attention: "supporting",
      role: "normal",
      status: "none"
    },
    {
      content: "是否把新协议设为唯一存储格式？",
      attention: "supporting",
      role: "decision",
      status: "none"
    },
    {
      content: "实现位于 `src/server/openrouter.ts`。",
      attention: "detail",
      role: "reference",
      status: "none"
    }
  ]
};

describe("AttentionDocumentView", () => {
  it("uses semantic attention levels instead of Markdown emphasis", () => {
    render(<AttentionDocumentView document={sampleDocument} focusLevel={0.9} />);

    expect(screen.getByText("代码已经修改并通过测试。").closest("section"))
      .toHaveAttribute("data-attention", "essential");
    expect(screen.getByText("已完成")).toBeInTheDocument();
    expect(screen.getByText("需要你决定")).toBeInTheDocument();
    expect(screen.queryByText("模型输入只包含问题和最终回答。")).toBeNull();
    expect(screen.queryByText(/实现位于/)).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "展开其余 2 条信息" }));
    expect(screen.getByText("模型输入只包含问题和最终回答。")).toBeInTheDocument();
    expect(screen.getByText(/实现位于/)).toBeInTheDocument();
  });

  it("shows every knowledge layer at the lowest focus", () => {
    render(<AttentionDocumentView document={sampleDocument} focusLevel={0} />);
    expect(globalThis.document.querySelectorAll("[data-attention]")).toHaveLength(4);
    expect(screen.queryByRole("button", { name: /展开其余/ })).toBeNull();
  });

  it("localizes semantic labels and expansion controls in English", () => {
    render(
      <AttentionDocumentView
        document={sampleDocument}
        focusLevel={0.9}
        language="en"
      />
    );

    expect(screen.getByText("Done")).toBeInTheDocument();
    expect(screen.getByText("Decision needed")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Show 2 more items" })).toBeInTheDocument();
  });
});
