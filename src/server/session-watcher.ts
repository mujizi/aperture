import { createHash } from "node:crypto";
import { watch, type FSWatcher } from "node:fs";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import type { AgentEvent } from "../core/types.js";
import { cleanQuestion } from "./events.js";
import {
  redactSensitiveText,
  redactSensitiveValue
} from "./redaction.js";

interface RolloutRow {
  timestamp?: string;
  type?: string;
  payload?: Record<string, unknown>;
}

export interface ObservedCodexTurn {
  runId: string;
  turnId: string;
  cwd: string;
  transcriptPath: string;
  completedAt: string;
  events: AgentEvent[];
}

interface SessionWatcherOptions {
  sessionsDir: string;
  isEnabled: () => boolean;
  shouldProcess: (turn: ObservedCodexTurn) => boolean;
  hasReview: (runId: string, turnId: string) => Promise<boolean>;
  onTurn: (turn: ObservedCodexTurn) => Promise<void>;
  onError?: (error: unknown) => void;
}

function stableId(...parts: string[]) {
  return createHash("sha256").update(parts.join("\u0000")).digest("hex").slice(0, 32);
}

function isoTimestamp(value: unknown, fallback: string) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value > 1_000_000_000_000 ? value : value * 1000).toISOString();
  }
  if (typeof value === "string") {
    const numeric = Number(value);
    if (value.trim() && Number.isFinite(numeric)) {
      return new Date(
        numeric > 1_000_000_000_000 ? numeric : numeric * 1000
      ).toISOString();
    }
    if (!Number.isNaN(Date.parse(value))) return new Date(value).toISOString();
  }
  return fallback;
}

function parseJson(value: unknown): unknown {
  if (typeof value !== "string") return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function excerpt(value: unknown, limit = 1600) {
  const text = redactSensitiveText(
    typeof value === "string"
      ? value
      : (() => {
          try {
            return JSON.stringify(value);
          } catch {
            return String(value);
          }
        })()
  );
  return text.length > limit ? `${text.slice(0, limit)}…` : text;
}

function toolEvents(
  rows: RolloutRow[],
  runId: string,
  turnId: string,
  cwd: string
): AgentEvent[] {
  const outputs = new Map<string, unknown>();
  for (const row of rows) {
    if (row.type !== "response_item") continue;
    const payload = row.payload ?? {};
    const payloadType = String(payload.type ?? "");
    if (!["function_call_output", "custom_tool_call_output"].includes(payloadType)) {
      continue;
    }
    const callId = String(payload.call_id ?? payload.id ?? "");
    if (callId) outputs.set(callId, payload.output);
  }

  const events: AgentEvent[] = [];
  for (const row of rows) {
    if (row.type !== "response_item") continue;
    const payload = row.payload ?? {};
    const payloadType = String(payload.type ?? "");
    if (!["function_call", "custom_tool_call"].includes(payloadType)) continue;
    const callId = String(payload.call_id ?? payload.id ?? stableId(JSON.stringify(payload)));
    const toolName = String(payload.name ?? payload.tool_name ?? "codex_tool");
    const input = redactSensitiveValue(
      parseJson(payload.arguments ?? payload.input ?? {})
    );
    const response = redactSensitiveValue(outputs.get(callId) ?? null);
    const id = stableId(runId, turnId, "tool", callId);
    events.push({
      id,
      source: "codex",
      runId,
      turnId,
      timestamp: row.timestamp ?? new Date().toISOString(),
      type: "tool_result",
      payload: {
        tool_name: toolName,
        tool_input: input,
        tool_response: response,
        cwd,
        capture_source: "codex_rollout"
      },
      parentEventId: null
    });
  }
  return events;
}

export function parseCompletedTurns(
  content: string,
  transcriptPath: string
): ObservedCodexTurn[] {
  const rows = content
    .split("\n")
    .filter(Boolean)
    .flatMap((line) => {
      try {
        return [JSON.parse(line) as RolloutRow];
      } catch {
        return [];
      }
    });
  const meta = rows.find((row) => row.type === "session_meta")?.payload ?? {};
  if (String(meta.thread_source ?? "user") !== "user") return [];

  const runId = String(meta.session_id ?? meta.id ?? "");
  const defaultCwd = String(meta.cwd ?? "");
  if (!runId) return [];

  const turns: ObservedCodexTurn[] = [];
  for (let end = 0; end < rows.length; end += 1) {
    const completion = rows[end];
    if (
      completion.type !== "event_msg" ||
      completion.payload?.type !== "task_complete"
    ) {
      continue;
    }
    const turnId = String(completion.payload.turn_id ?? "");
    if (!turnId) continue;

    let start = end;
    while (start > 0) {
      const row = rows[start];
      if (
        row.type === "event_msg" &&
        row.payload?.type === "task_started" &&
        String(row.payload.turn_id ?? "") === turnId
      ) {
        break;
      }
      start -= 1;
    }
    const turnRows = rows.slice(start, end + 1);
    const context = [...turnRows]
      .reverse()
      .find((row) => row.type === "turn_context")?.payload;
    const cwd = String(context?.cwd ?? defaultCwd);
    const completedAt = isoTimestamp(
      completion.payload.completed_at ?? completion.timestamp,
      new Date().toISOString()
    );
    const seenPrompts = new Set<string>();
    const prompts = turnRows.flatMap((row) => {
      if (
        row.type !== "event_msg" ||
        row.payload?.type !== "user_message"
      ) {
        return [];
      }
      const prompt = redactSensitiveText(
        cleanQuestion(String(row.payload.message ?? ""))
      );
      if (!prompt || seenPrompts.has(prompt)) return [];
      seenPrompts.add(prompt);
      return [{ prompt, timestamp: row.timestamp ?? completedAt }];
    });
    const assistant = redactSensitiveText(
      String(completion.payload.last_agent_message ?? "")
    );

    const sessionId = stableId(runId, turnId, "session");
    const promptEvents: AgentEvent[] = prompts.map((entry, index) => ({
      id: stableId(runId, turnId, "prompt", String(index), entry.prompt),
      source: "codex",
      runId,
      turnId,
      timestamp: entry.timestamp,
      type: "user_prompt",
      payload: {
        prompt: entry.prompt,
        cwd,
        capture_source: "codex_rollout"
      },
      parentEventId: sessionId
    }));
    const stopId = stableId(runId, turnId, "stop");
    const events: AgentEvent[] = [
      {
        id: sessionId,
        source: "codex",
        runId,
        turnId: null,
        timestamp: isoTimestamp(
          meta.timestamp ?? turnRows[0]?.timestamp,
          completedAt
        ),
        type: "session_start",
        payload: {
          cwd,
          transcript_path: transcriptPath,
          capture_source: "codex_rollout"
        },
        parentEventId: null
      },
      ...promptEvents,
      ...toolEvents(turnRows, runId, turnId, cwd),
      {
        id: stopId,
        source: "codex",
        runId,
        turnId,
        timestamp: completedAt,
        type: "assistant_stop",
        payload: {
          last_assistant_message: assistant,
          cwd,
          transcript_path: transcriptPath,
          capture_source: "codex_rollout"
        },
        parentEventId: promptEvents.at(-1)?.id ?? sessionId
      }
    ];
    turns.push({
      runId,
      turnId,
      cwd,
      transcriptPath,
      completedAt,
      events
    });
  }
  return turns;
}

export class CodexSessionWatcher {
  private watcher: FSWatcher | null = null;
  private reconcileTimer: NodeJS.Timeout | null = null;
  private readonly pending = new Map<string, NodeJS.Timeout>();
  private readonly processing = new Set<string>();

  constructor(private readonly options: SessionWatcherOptions) {}

  async start() {
    await this.initialScan();
    try {
      this.watcher = watch(
        this.options.sessionsDir,
        { recursive: true },
        (_event, filename) => {
          if (!filename?.endsWith(".jsonl")) return;
          this.schedule(path.join(this.options.sessionsDir, filename));
        }
      );
      this.watcher.on("error", (error) => this.options.onError?.(error));
    } catch (error) {
      this.options.onError?.(error);
    }
    this.reconcileTimer = setInterval(() => {
      void this.scanRecentFiles(10 * 60 * 1000);
    }, 2000);
    this.reconcileTimer.unref();
  }

  close() {
    this.watcher?.close();
    this.watcher = null;
    if (this.reconcileTimer) clearInterval(this.reconcileTimer);
    this.reconcileTimer = null;
    for (const timer of this.pending.values()) clearTimeout(timer);
    this.pending.clear();
  }

  private schedule(filePath: string) {
    if (!this.options.isEnabled()) return;
    const existing = this.pending.get(filePath);
    if (existing) clearTimeout(existing);
    const timer = setTimeout(() => {
      this.pending.delete(filePath);
      void this.processFile(filePath);
    }, 90);
    this.pending.set(filePath, timer);
  }

  private async initialScan() {
    await this.scanRecentFiles(12 * 60 * 60 * 1000);
  }

  private async scanRecentFiles(maxAgeMs: number) {
    if (!this.options.isEnabled()) return;
    let entries;
    try {
      entries = await readdir(this.options.sessionsDir, {
        recursive: true,
        withFileTypes: true
      });
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
        this.options.onError?.(error);
      }
      return;
    }
    const cutoff = Date.now() - maxAgeMs;
    const candidates: Array<{ filePath: string; modified: number }> = [];
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".jsonl")) continue;
      const parentPath =
        "parentPath" in entry && typeof entry.parentPath === "string"
          ? entry.parentPath
          : this.options.sessionsDir;
      const filePath = path.join(parentPath, entry.name);
      try {
        const info = await stat(filePath);
        if (info.mtimeMs >= cutoff) {
          candidates.push({ filePath, modified: info.mtimeMs });
        }
      } catch {
        // The rollout may be moving between atomic writes.
      }
    }
    candidates.sort((left, right) => left.modified - right.modified);
    for (const candidate of candidates) {
      await this.processFile(candidate.filePath);
    }
  }

  private async processFile(filePath: string) {
    if (!this.options.isEnabled() || this.processing.has(filePath)) return;
    this.processing.add(filePath);
    try {
      const turns = parseCompletedTurns(await readFile(filePath, "utf8"), filePath);
      for (const turn of turns) {
        if (!this.options.isEnabled()) return;
        if (!this.options.shouldProcess(turn)) continue;
        if (await this.options.hasReview(turn.runId, turn.turnId)) continue;
        await this.options.onTurn(turn);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
        this.options.onError?.(error);
      }
    } finally {
      this.processing.delete(filePath);
    }
  }
}
