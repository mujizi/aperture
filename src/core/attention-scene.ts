import type {
  AttentionScene,
  ComparisonVisualNode,
  FlowVisualNode,
  MetricsVisualNode,
  StatementVisualNode,
  VisualNode
} from "./types.js";

function gateMarkdown(scene: AttentionScene) {
  const gate = scene.gate;
  if (gate.kind === "none") return "";
  const label = gate.kind === "decision" ? "需要你决定" : "阻塞";
  const options = gate.options.length
    ? `\n${gate.options.map((option) => `- ${option}`).join("\n")}`
    : "";
  return `> **${label}：${gate.title}**${gate.detail ? `\n> ${gate.detail}` : ""}${options}`;
}

function statementMarkdown(node: StatementVisualNode) {
  return `### ${node.label}\n\n${node.text}`;
}

function flowMarkdown(node: FlowVisualNode) {
  return [
    `### ${node.label}`,
    "",
    node.steps
      .map((step, index) =>
        `${index + 1}. **${step.label}**${step.detail ? `：${step.detail}` : ""}`
      )
      .join("\n")
  ].join("\n");
}

function escapeTable(value: string) {
  return value.replaceAll("|", "\\|").replaceAll("\n", " ");
}

function comparisonMarkdown(node: ComparisonVisualNode) {
  return [
    `### ${node.label}`,
    "",
    `| 对比项 | ${escapeTable(node.leftLabel)} | ${escapeTable(node.rightLabel)} |`,
    "|---|---|---|",
    ...node.rows.map(
      (row) =>
        `| ${escapeTable(row.aspect)} | ${escapeTable(row.left)} | ${escapeTable(row.right)} |`
    )
  ].join("\n");
}

function metricsMarkdown(node: MetricsVisualNode) {
  return [
    `### ${node.label}`,
    "",
    ...node.items.map((item) => `- **${item.value}** ${item.label}`)
  ].join("\n");
}

function visualNodeMarkdown(node: VisualNode) {
  if (node.kind === "flow") return flowMarkdown(node);
  if (node.kind === "comparison") return comparisonMarkdown(node);
  if (node.kind === "metrics") return metricsMarkdown(node);
  return statementMarkdown(node);
}

export function attentionSceneToMarkdown(scene: AttentionScene) {
  return [
    `**${scene.spotlight.text}**`,
    gateMarkdown(scene),
    ...scene.views.map(visualNodeMarkdown)
  ]
    .filter(Boolean)
    .join("\n\n")
    .trim();
}
