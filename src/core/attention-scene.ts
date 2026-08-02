import type {
  AppLanguage,
  AttentionScene,
  ComparisonVisualNode,
  FlowVisualNode,
  MetricsVisualNode,
  StatementVisualNode,
  VisualNode
} from "./types.js";

function gateMarkdown(scene: AttentionScene, language: AppLanguage) {
  const gate = scene.gate;
  if (gate.kind === "none") return "";
  const label = language === "en"
    ? (gate.kind === "decision" ? "Decision needed" : "Blocked")
    : (gate.kind === "decision" ? "需要你决定" : "阻塞");
  const options = gate.options.length
    ? `\n${gate.options.map((option) => `- ${option}`).join("\n")}`
    : "";
  const separator = language === "en" ? ": " : "：";
  return `> **${label}${separator}${gate.title}**${gate.detail ? `\n> ${gate.detail}` : ""}${options}`;
}

function statementMarkdown(node: StatementVisualNode) {
  return `### ${node.label}\n\n${node.text}`;
}

function flowMarkdown(node: FlowVisualNode, language: AppLanguage) {
  return [
    `### ${node.label}`,
    "",
    node.steps
      .map((step, index) =>
        `${index + 1}. **${step.label}**${step.detail ? `${language === "en" ? ": " : "："}${step.detail}` : ""}`
      )
      .join("\n")
  ].join("\n");
}

function escapeTable(value: string) {
  return value.replaceAll("|", "\\|").replaceAll("\n", " ");
}

function comparisonMarkdown(node: ComparisonVisualNode, language: AppLanguage) {
  return [
    `### ${node.label}`,
    "",
    `| ${language === "en" ? "Comparison" : "对比项"} | ${escapeTable(node.leftLabel)} | ${escapeTable(node.rightLabel)} |`,
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

function visualNodeMarkdown(node: VisualNode, language: AppLanguage) {
  if (node.kind === "flow") return flowMarkdown(node, language);
  if (node.kind === "comparison") return comparisonMarkdown(node, language);
  if (node.kind === "metrics") return metricsMarkdown(node);
  return statementMarkdown(node);
}

export function attentionSceneToMarkdown(
  scene: AttentionScene,
  language: AppLanguage = "cn"
) {
  return [
    `**${scene.spotlight.text}**`,
    gateMarkdown(scene, language),
    ...scene.views.map((node) => visualNodeMarkdown(node, language))
  ]
    .filter(Boolean)
    .join("\n\n")
    .trim();
}
