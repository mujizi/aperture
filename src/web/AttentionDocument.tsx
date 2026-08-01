import { useEffect, useState } from "react";
import {
  hiddenAttentionBlockCount,
  visibleAttentionBlocks
} from "../core/attention-document";
import type {
  AttentionBlock,
  AttentionDocument
} from "../core/types";
import { InlineMarkdown } from "./AttentionMarkdown";

const roleLabels: Partial<Record<AttentionBlock["role"], string>> = {
  decision: "需要你决定",
  action: "下一步",
  risk: "风险",
  blocker: "阻塞",
  reference: "参考"
};

const statusLabels: Partial<Record<AttentionBlock["status"], string>> = {
  done: "已完成",
  partial: "部分完成",
  proposed: "方案",
  unverified: "未验证"
};

function AttentionUnit({
  block,
  lead
}: {
  block: AttentionBlock;
  lead: boolean;
}) {
  const roleLabel = roleLabels[block.role];
  const statusLabel = statusLabels[block.status];
  return (
    <section
      className={[
        "attention-unit",
        `attention-unit--${block.attention}`,
        `attention-unit--role-${block.role}`,
        lead ? "attention-unit--lead" : ""
      ].filter(Boolean).join(" ")}
      data-attention={block.attention}
    >
      {(roleLabel || statusLabel) && (
        <header className="attention-unit-meta">
          {roleLabel && <span className="attention-role">{roleLabel}</span>}
          {statusLabel && <span className="attention-status">{statusLabel}</span>}
        </header>
      )}
      <div className="attention-unit-content">
        <InlineMarkdown source={block.content} />
      </div>
    </section>
  );
}

export function AttentionDocumentView({
  document,
  focusLevel
}: {
  document: AttentionDocument;
  focusLevel: number;
}) {
  const [expanded, setExpanded] = useState(false);
  const visible = expanded
    ? document.blocks
    : visibleAttentionBlocks(document, focusLevel);
  const hidden = expanded ? 0 : hiddenAttentionBlockCount(document, focusLevel);
  const leadIndex = visible.findIndex((block) => block.attention === "essential");

  useEffect(() => setExpanded(false), [document, focusLevel]);

  return (
    <div className="attention-document">
      {visible.map((block, index) => (
        <AttentionUnit
          block={block}
          key={`${index}:${block.role}:${block.content.slice(0, 24)}`}
          lead={index === leadIndex}
        />
      ))}
      {hidden > 0 && (
        <button
          className="attention-more"
          onClick={() => setExpanded(true)}
          type="button"
        >
          展开其余 {hidden} 条信息
        </button>
      )}
    </div>
  );
}
