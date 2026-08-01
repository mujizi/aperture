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

export interface ReviewSnapshot {
  id: string;
  runId: string;
  turnId: string | null;
  projectName?: string;
  projectPath?: string;
  generatedAt: string;
  sourceCompletedAt?: string;
  resultMarkdown: string;
  analysis: {
    mode: "model" | "error";
    model: string | null;
    durationMs: number;
    error: string | null;
  };
}
