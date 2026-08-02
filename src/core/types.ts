export interface AgentEvent {
  id: string;
  source: "codex" | "claude-code" | "cursor" | "manual";
  runId: string;
  turnId: string | null;
  timestamp: string;
  type:
    | "session_start"
    | "user_prompt"
    | "tool_result"
    | "assistant_stop"
    | "analysis_started"
    | "analysis_completed"
    | "feedback";
  payload: Record<string, unknown>;
  parentEventId: string | null;
}

export type AppLanguage = "cn" | "en";

export type AttentionLevel = "essential" | "supporting" | "detail";

export type AttentionRole =
  | "normal"
  | "outcome"
  | "decision"
  | "action"
  | "risk"
  | "blocker"
  | "reference";

export type AttentionStatus =
  | "none"
  | "done"
  | "partial"
  | "proposed"
  | "unverified";

export interface AttentionBlock {
  content: string;
  attention: AttentionLevel;
  role: AttentionRole;
  status: AttentionStatus;
}

export interface AttentionDocument {
  version: 1;
  blocks: AttentionBlock[];
}

export type SceneStatus =
  | "none"
  | "done"
  | "partial"
  | "proposed"
  | "unverified";

export type SceneTone = "neutral" | "change" | "risk" | "verified";

export type HighlightTone = "key" | "change" | "decision" | "risk" | "verified";

export interface TextHighlight {
  phrase: string;
  tone: HighlightTone;
}

export interface SceneSpotlight {
  label: string;
  text: string;
  status: SceneStatus;
  highlights: TextHighlight[];
}

export interface SceneGate {
  kind: "none" | "decision" | "blocker";
  title: string;
  detail: string;
  options: string[];
}

interface VisualNodeBase {
  label: string;
  attention: "supporting" | "context";
  status: SceneStatus;
  tone: SceneTone;
}

export interface StatementVisualNode extends VisualNodeBase {
  kind: "statement";
  text: string;
  highlights: TextHighlight[];
}

export interface FlowVisualNode extends VisualNodeBase {
  kind: "flow";
  steps: Array<{
    label: string;
    detail: string;
    tone: SceneTone;
  }>;
}

export interface ComparisonVisualNode extends VisualNodeBase {
  kind: "comparison";
  leftLabel: string;
  rightLabel: string;
  rows: Array<{
    aspect: string;
    left: string;
    right: string;
    change: "better" | "worse" | "different" | "same";
  }>;
}

export interface MetricsVisualNode extends VisualNodeBase {
  kind: "metrics";
  items: Array<{
    label: string;
    value: string;
    tone: SceneTone;
  }>;
}

export type VisualNode =
  | StatementVisualNode
  | FlowVisualNode
  | ComparisonVisualNode
  | MetricsVisualNode;

export interface AttentionScene {
  version: 2;
  spotlight: SceneSpotlight;
  gate: SceneGate;
  views: VisualNode[];
}

export interface ReviewSnapshot {
  id: string;
  runId: string;
  turnId: string | null;
  projectName?: string;
  projectPath?: string;
  generatedAt: string;
  language?: AppLanguage;
  sourceCompletedAt?: string;
  attentionScene?: AttentionScene;
  attentionDocument?: AttentionDocument;
  resultMarkdown: string;
  analysis: {
    mode: "model" | "error";
    model: string | null;
    durationMs: number;
    error: string | null;
  };
}
