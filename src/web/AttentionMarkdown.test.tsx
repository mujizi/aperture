// @vitest-environment jsdom

import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AttentionMarkdown, parseAttentionMarkdown } from "./AttentionMarkdown";

describe("AttentionMarkdown", () => {
  it("turns the first short conclusion into the lead and groups supporting items", () => {
    render(
      <AttentionMarkdown
        source={[
          "**红烧肉选题缺少一条中心主线**",
          "",
          "围绕文化符号重构论述。",
          "",
          "- 保留地域差异",
          "- 保留身份想象"
        ].join("\n")}
      />
    );

    expect(screen.getByText("红烧肉选题缺少一条中心主线").closest("p"))
      .toHaveClass("attention-lead");
    expect(screen.getByRole("list")).toHaveClass("attention-list");
    expect(screen.getAllByRole("listitem")).toHaveLength(2);
  });

  it("renders decisions and blockers as semantic callouts", () => {
    const { rerender } = render(
      <AttentionMarkdown source="> **需要你决定：是否发布当前版本**" />
    );
    expect(screen.getByRole("note")).toHaveClass("attention-callout--action");

    rerender(<AttentionMarkdown source="> **阻塞：构建仍然失败**" />);
    expect(screen.getByRole("note")).toHaveClass("attention-callout--blocker");
  });

  it("demotes reference lines, bare URLs, and path-only code blocks", () => {
    render(
      <AttentionMarkdown
        source={[
          "**应用已经重新安装**",
          "",
          "参考：`/Applications/Aperture.app` · https://example.com/docs",
          "",
          "```",
          "/Users/example/project/result.md",
          "```"
        ].join("\n")}
      />
    );

    expect(screen.getByText(/参考：/).closest("p")).toHaveClass(
      "attention-reference"
    );
    expect(screen.getByRole("link")).toHaveAttribute(
      "href",
      "https://example.com/docs"
    );
    expect(screen.getByText("/Users/example/project/result.md").closest("pre"))
      .toHaveClass("attention-reference-block");
  });

  it("does not promote a legacy long paragraph into a giant lead", () => {
    const source = "这是一个没有分层的旧结果。".repeat(8);
    const blocks = parseAttentionMarkdown(source);
    expect(blocks).toHaveLength(1);

    render(<AttentionMarkdown source={source} />);
    expect(screen.getByText(source)).toHaveClass("attention-copy");
  });
});
