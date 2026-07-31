import { randomUUID } from "node:crypto";
import type { AgentEvent } from "../core/types.js";

function stringValue(value: unknown) {
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function excerpt(value: unknown, limit = 500) {
  const text = stringValue(value).replace(/\s+/g, " ").trim();
  return text.length > limit ? `${text.slice(0, limit)}…` : text;
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

export function compactEvent(event: AgentEvent) {
  const payload = event.payload;
  if (event.type === "tool_result") {
    return {
      id: event.id,
      type: event.type,
      tool: payload.tool_name,
      input: excerpt(payload.tool_input, 900),
      response: excerpt(payload.tool_response, 1200)
    };
  }
  if (event.type === "assistant_stop") {
    return {
      id: event.id,
      type: event.type,
      message: excerpt(payload.last_assistant_message, 2400)
    };
  }
  if (event.type === "user_prompt") {
    return {
      id: event.id,
      type: event.type,
      prompt: excerpt(payload.prompt, 1800)
    };
  }
  return { id: event.id, type: event.type, payload: excerpt(payload, 800) };
}
