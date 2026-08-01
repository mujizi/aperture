import { randomUUID } from "node:crypto";
import type { AgentEvent } from "../core/types.js";

export function cleanQuestion(value: string) {
  return value
    .replace(
      /<in-app-browser-context\b[^>]*>[\s\S]*?<\/in-app-browser-context>/gi,
      ""
    )
    .replace(
      /<environment_context\b[^>]*>[\s\S]*?<\/environment_context>/gi,
      ""
    )
    .replace(
      /<recommended_plugins\b[^>]*>[\s\S]*?<\/recommended_plugins>/gi,
      ""
    )
    .replace(
      /^\s*#\s+Files mentioned by the user:\s*[\s\S]*?^\s*##\s+My request for Codex:\s*/im,
      ""
    )
    .replace(/^\s*##\s+My request for Codex:\s*/im, "")
    .trim();
}

export function eventFromHook(input: Record<string, unknown>): AgentEvent {
  const hookName = String(input.hook_event_name ?? "");
  const type: AgentEvent["type"] =
    hookName === "SessionStart"
      ? "session_start"
      : hookName === "UserPromptSubmit"
        ? "user_prompt"
        : hookName === "Stop"
          ? "assistant_stop"
          : "tool_result";

  return {
    id: randomUUID(),
    source: "codex",
    runId: String(input.session_id ?? "unknown-session"),
    turnId: input.turn_id ? String(input.turn_id) : null,
    timestamp: new Date().toISOString(),
    type,
    payload: input,
    parentEventId: null
  };
}

export function manualEvent(
  type: AgentEvent["type"],
  payload: Record<string, unknown>,
  runId = "manual",
  turnId: string | null = null
): AgentEvent {
  return {
    id: randomUUID(),
    source: "manual",
    runId,
    turnId,
    timestamp: new Date().toISOString(),
    type,
    payload,
    parentEventId: null
  };
}
