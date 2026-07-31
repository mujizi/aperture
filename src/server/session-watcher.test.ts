import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  CodexSessionWatcher,
  parseCompletedTurns
} from "./session-watcher";

const tempDirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    tempDirs.splice(0).map((directory) =>
      rm(directory, { recursive: true, force: true })
    )
  );
});

describe("Codex rollout watcher", () => {
  it("turns a completed desktop task into Aperture events", () => {
    const rows = [
      {
        timestamp: "2026-07-31T06:13:44.808Z",
        type: "session_meta",
        payload: {
          session_id: "thread-1",
          cwd: "/tmp/test007",
          thread_source: "user"
        }
      },
      {
        timestamp: "2026-07-31T06:13:48.000Z",
        type: "event_msg",
        payload: { type: "task_started", turn_id: "turn-1" }
      },
      {
        timestamp: "2026-07-31T06:13:49.000Z",
        type: "event_msg",
        payload: { type: "user_message", message: "红烧肉怎么做" }
      },
      {
        timestamp: "2026-07-31T06:13:53.000Z",
        type: "event_msg",
        payload: {
          type: "task_complete",
          turn_id: "turn-1",
          last_agent_message: "先焯水，再炒糖色，最后小火慢炖。"
        }
      }
    ];

    const turns = parseCompletedTurns(
      rows.map((row) => JSON.stringify(row)).join("\n"),
      "/tmp/rollout.jsonl"
    );

    expect(turns).toHaveLength(1);
    expect(turns[0].runId).toBe("thread-1");
    expect(turns[0].turnId).toBe("turn-1");
    expect(turns[0].events.map((event) => event.type)).toEqual([
      "session_start",
      "user_prompt",
      "assistant_stop"
    ]);
    expect(turns[0].events[1].payload.prompt).toBe("红烧肉怎么做");
    expect(turns[0].events[2].payload.last_assistant_message).toContain("炒糖色");
  });

  it("redacts credentials before session content enters the event store", () => {
    const rows = [
      {
        timestamp: "2026-07-31T06:00:00.000Z",
        type: "session_meta",
        payload: {
          session_id: "run-secret",
          cwd: "/tmp/test",
          thread_source: "user"
        }
      },
      {
        timestamp: "2026-07-31T06:00:01.000Z",
        type: "event_msg",
        payload: { type: "task_started", turn_id: "turn-secret" }
      },
      {
        timestamp: "2026-07-31T06:00:02.000Z",
        type: "event_msg",
        payload: {
          type: "user_message",
          message: "Use sk-or-v1-example_secret_1234567890"
        }
      },
      {
        timestamp: "2026-07-31T06:00:03.000Z",
        type: "event_msg",
        payload: {
          type: "task_complete",
          turn_id: "turn-secret",
          last_agent_message: "Configured sk-or-v1-another_secret_1234567890"
        }
      }
    ];

    const [turn] = parseCompletedTurns(
      rows.map((row) => JSON.stringify(row)).join("\n"),
      "/tmp/secret.jsonl"
    );
    const serialized = JSON.stringify(turn.events);
    expect(serialized).not.toContain("example_secret");
    expect(serialized).not.toContain("another_secret");
    expect(serialized).toContain("[REDACTED_OPENROUTER_KEY]");
  });

  it("does not read or process completed turns while monitoring is disabled", async () => {
    const sessionsDir = await mkdtemp(
      path.join(os.tmpdir(), "aperture-sessions-")
    );
    tempDirs.push(sessionsDir);
    const filePath = path.join(sessionsDir, "rollout-disabled.jsonl");
    const rows = [
      {
        timestamp: "2026-07-31T06:00:00.000Z",
        type: "session_meta",
        payload: {
          session_id: "run-disabled",
          cwd: "/tmp/test",
          thread_source: "user"
        }
      },
      {
        timestamp: "2026-07-31T06:00:01.000Z",
        type: "event_msg",
        payload: { type: "task_started", turn_id: "turn-disabled" }
      },
      {
        timestamp: "2026-07-31T06:00:02.000Z",
        type: "event_msg",
        payload: { type: "user_message", message: "Should be skipped" }
      },
      {
        timestamp: "2026-07-31T06:00:03.000Z",
        type: "event_msg",
        payload: {
          type: "task_complete",
          turn_id: "turn-disabled",
          last_agent_message: "Done"
        }
      }
    ];
    await writeFile(
      filePath,
      rows.map((row) => JSON.stringify(row)).join("\n"),
      "utf8"
    );

    const observed: string[] = [];
    const watcher = new CodexSessionWatcher({
      sessionsDir,
      isEnabled: () => false,
      shouldProcess: () => true,
      hasReview: async () => false,
      onTurn: async (turn) => {
        observed.push(turn.turnId);
      }
    });
    await watcher.start();
    watcher.close();

    expect(observed).toEqual([]);
  });
});
