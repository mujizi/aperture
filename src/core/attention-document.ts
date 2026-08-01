import type {
  AttentionBlock,
  AttentionDocument,
  AttentionLevel
} from "./types.js";

const attentionRank: Record<AttentionLevel, number> = {
  essential: 0,
  supporting: 1,
  detail: 2
};

function isPinned(block: AttentionBlock) {
  return block.role === "decision" || block.role === "blocker";
}

export function visibleAttentionBlocks(
  document: AttentionDocument,
  focusLevel: number
) {
  const focus = Math.min(1, Math.max(0, focusLevel));
  const maximumRank = focus >= 0.78 ? 0 : focus >= 0.38 ? 1 : 2;
  return document.blocks.filter(
    (block) => isPinned(block) || attentionRank[block.attention] <= maximumRank
  );
}

export function hiddenAttentionBlockCount(
  document: AttentionDocument,
  focusLevel: number
) {
  return document.blocks.length - visibleAttentionBlocks(document, focusLevel).length;
}

function markdownForBlock(block: AttentionBlock, index: number) {
  if (block.role === "decision") return `> **需要你决定：** ${block.content}`;
  if (block.role === "blocker") return `> **阻塞：** ${block.content}`;
  if (block.role === "risk") return `> **风险：** ${block.content}`;
  if (block.role === "action") return `- **下一步：** ${block.content}`;
  if (block.role === "reference") return `参考：${block.content}`;
  if (index === 0 || block.role === "outcome") return `**${block.content}**`;
  return `- ${block.content}`;
}

export function attentionDocumentToMarkdown(document: AttentionDocument) {
  return document.blocks
    .map(markdownForBlock)
    .join("\n\n")
    .trim();
}
