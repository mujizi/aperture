import { useEffect, useState } from "react";
import {
  hiddenAttentionBlockCount,
  visibleAttentionBlocks
} from "../core/attention-document";
import type {
  AppLanguage,
  AttentionBlock,
  AttentionDocument
} from "../core/types";
import { InlineMarkdown } from "./AttentionMarkdown";
import { ui } from "./i18n";

function labels(language: AppLanguage) {
  const value = ui(language);
  return {
    roles: { decision: value.decision, action: value.action, risk: value.risk, blocker: value.blocker, reference: value.reference },
    statuses: { done: value.done, partial: value.partial, proposed: value.proposed, unverified: value.unverified }
  };
}

function AttentionUnit({
  block,
  lead,
  language
}: {
  block: AttentionBlock;
  lead: boolean;
  language: AppLanguage;
}) {
  const translated = labels(language);
  const roleLabel = translated.roles[block.role as keyof typeof translated.roles];
  const statusLabel = translated.statuses[block.status as keyof typeof translated.statuses];
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
  focusLevel,
  language = "cn"
}: {
  document: AttentionDocument;
  focusLevel: number;
  language?: AppLanguage;
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
          language={language}
        />
      ))}
      {hidden > 0 && (
        <button
          className="attention-more"
          onClick={() => setExpanded(true)}
          type="button"
        >
          {ui(language).showMore(hidden)}
        </button>
      )}
    </div>
  );
}
