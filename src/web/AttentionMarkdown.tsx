import type { ReactNode } from "react";

type CalloutTone = "action" | "blocker" | "uncertain" | "note";

type MarkdownBlock =
  | { type: "heading"; level: number; text: string }
  | { type: "paragraph"; text: string; reference: boolean }
  | { type: "quote"; text: string; tone: CalloutTone }
  | { type: "list"; ordered: boolean; items: string[] }
  | { type: "code"; language: string; value: string; reference: boolean }
  | { type: "rule" };

const referencePrefix =
  /^(?:参考|路径|文件|链接|网址|地址|命令|版本|日志|产物|位置|reference|path|file|url|command|version|artifact)\s*[:：]/i;

function plainText(value: string) {
  return value
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .trim();
}

function isReferenceText(value: string) {
  const text = value.trim();
  if (referencePrefix.test(plainText(text))) return true;
  if (/^(?:`[^`]+`\s*(?:[,，、·|]\s*)?)+$/.test(text)) return true;
  return /^(?:https?:\/\/\S+\s*)+$/.test(text);
}

function isReferenceCode(value: string) {
  const lines = value
    .trim()
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  if (!lines.length || lines.length > 4) return false;
  return lines.every((line) =>
    /^(?:https?:\/\/|file:\/\/|~\/|\.\.?\/|\/|[A-Za-z]:\\|[\w.@-]+\/[\w./@-]+|(?:path|file|url|command)\s*[:=])/i.test(
      line
    )
  );
}

function calloutTone(value: string): CalloutTone {
  const text = plainText(value);
  if (/^(?:阻塞|失败|无法继续|严重风险|高风险)\s*[:：]?/.test(text)) {
    return "blocker";
  }
  if (/^(?:需要你(?:决定|确认|介入)|需要决定|请决定|下一步|行动)\s*[:：]?/.test(text)) {
    return "action";
  }
  if (/^(?:不确定|未验证|未知|待确认)\s*[:：]?/.test(text)) {
    return "uncertain";
  }
  return "note";
}

export function parseAttentionMarkdown(source: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  const lines = source.replace(/\r\n?/g, "\n").split("\n");
  let paragraph: string[] = [];
  let list: { ordered: boolean; items: string[] } | null = null;
  let quote: string[] = [];
  let code: string[] | null = null;
  let codeLanguage = "";

  const flushParagraph = () => {
    if (!paragraph.length) return;
    const text = paragraph.join(" ").trim();
    blocks.push({ type: "paragraph", text, reference: isReferenceText(text) });
    paragraph = [];
  };
  const flushList = () => {
    if (!list) return;
    blocks.push({ type: "list", ...list });
    list = null;
  };
  const flushQuote = () => {
    if (!quote.length) return;
    const text = quote.join(" ").trim();
    blocks.push({ type: "quote", text, tone: calloutTone(text) });
    quote = [];
  };
  const flushFlow = () => {
    flushParagraph();
    flushList();
    flushQuote();
  };

  for (const line of lines) {
    const value = line.trim();
    const fence = value.match(/^```([\w+-]*)$/);
    if (fence) {
      if (code) {
        const codeValue = code.join("\n");
        blocks.push({
          type: "code",
          language: codeLanguage,
          value: codeValue,
          reference: isReferenceCode(codeValue)
        });
        code = null;
        codeLanguage = "";
      } else {
        flushFlow();
        code = [];
        codeLanguage = fence[1];
      }
      continue;
    }
    if (code) {
      code.push(line);
      continue;
    }
    if (!value) {
      flushFlow();
      continue;
    }
    if (/^([-*_])\1{2,}$/.test(value)) {
      flushFlow();
      blocks.push({ type: "rule" });
      continue;
    }
    const heading = value.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      flushFlow();
      blocks.push({ type: "heading", level: heading[1].length, text: heading[2] });
      continue;
    }
    const quoteLine = value.match(/^>\s?(.+)$/);
    if (quoteLine) {
      flushParagraph();
      flushList();
      quote.push(quoteLine[1]);
      continue;
    }
    const bullet = value.match(/^[-*]\s+(.+)$/);
    const numbered = value.match(/^\d+[.)、]\s*(.+)$/);
    if (bullet || numbered) {
      flushParagraph();
      flushQuote();
      const ordered = Boolean(numbered);
      if (list && list.ordered !== ordered) flushList();
      list ??= { ordered, items: [] };
      list.items.push((bullet ?? numbered)![1]);
      continue;
    }
    flushList();
    flushQuote();
    paragraph.push(value);
  }

  if (code) {
    const codeValue = code.join("\n");
    blocks.push({
      type: "code",
      language: codeLanguage,
      value: codeValue,
      reference: isReferenceCode(codeValue)
    });
  }
  flushFlow();
  return blocks;
}

export function InlineMarkdown({ source }: { source: string }) {
  const tokens = source.split(
    /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\(https?:\/\/[^)\s]+\)|https?:\/\/[^\s<，。！？、；：）】》]+)/g
  );
  return tokens.map((token, index) => {
    const key = `${index}:${token.slice(0, 16)}`;
    if (token.startsWith("**") && token.endsWith("**")) {
      return <strong key={key}>{token.slice(2, -2)}</strong>;
    }
    if (token.startsWith("`") && token.endsWith("`")) {
      return <code key={key}>{token.slice(1, -1)}</code>;
    }
    const link = token.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/);
    if (link) {
      return (
        <a href={link[2]} key={key} rel="noreferrer" target="_blank">
          {link[1]}
        </a>
      );
    }
    if (/^https?:\/\//.test(token)) {
      return (
        <a href={token} key={key} rel="noreferrer" target="_blank">
          {token}
        </a>
      );
    }
    return token;
  });
}

function blockCanLead(block: MarkdownBlock) {
  return (
    block.type === "heading" ||
    (block.type === "paragraph" &&
      !block.reference &&
      plainText(block.text).length <= 56) ||
    block.type === "quote"
  );
}

export function AttentionMarkdown({ source }: { source: string }) {
  const blocks = parseAttentionMarkdown(source);
  const leadIndex = blocks.findIndex(blockCanLead);

  const nodes: ReactNode[] = blocks.map((block, index) => {
    const isLead = index === leadIndex;
    const key = `${index}:${block.type}`;
    if (block.type === "heading") {
      const Heading = `h${block.level}` as "h1" | "h2" | "h3" | "h4";
      return (
        <Heading className={isLead ? "attention-lead" : undefined} key={key}>
          <InlineMarkdown source={block.text} />
        </Heading>
      );
    }
    if (block.type === "paragraph") {
      return (
        <p
          className={
            block.reference
              ? "attention-reference"
              : isLead
                ? "attention-lead"
                : "attention-copy"
          }
          key={key}
        >
          <InlineMarkdown source={block.text} />
        </p>
      );
    }
    if (block.type === "quote") {
      return (
        <aside
          className={`attention-callout attention-callout--${block.tone} ${isLead ? "attention-lead" : ""}`}
          key={key}
          role="note"
        >
          <InlineMarkdown source={block.text} />
        </aside>
      );
    }
    if (block.type === "list") {
      const List = block.ordered ? "ol" : "ul";
      return (
        <List className="attention-list" key={key}>
          {block.items.map((item, itemIndex) => (
            <li
              className={isReferenceText(item) ? "attention-reference" : undefined}
              key={`${itemIndex}:${item.slice(0, 18)}`}
            >
              <InlineMarkdown source={item} />
            </li>
          ))}
        </List>
      );
    }
    if (block.type === "code") {
      return (
        <pre
          className={
            block.reference
              ? "attention-reference-block"
              : "simple-markdown-codeblock"
          }
          key={key}
        >
          <code data-language={block.language || undefined}>{block.value}</code>
        </pre>
      );
    }
    return <hr key={key} />;
  });

  return <div className="simple-markdown">{nodes}</div>;
}
