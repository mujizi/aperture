import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import type { ReviewSnapshot } from "../core/types";
import { EventStore } from "./store";

const tempDirs: string[] = [];

afterEach(async () => {
  const { rm } = await import("node:fs/promises");
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

describe("event store projections", () => {
  it("persists immutable review snapshots", async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), "aperture-store-"));
    tempDirs.push(dir);
    const store = new EventStore(dir);
    const review = {
      id: "review-1",
      runId: "run-1",
      turnId: "turn-1",
      generatedAt: new Date().toISOString(),
      resultMarkdown: "Completed the requested change.",
      analysis: { mode: "model", model: "test/model", durationMs: 1, error: null }
    } satisfies ReviewSnapshot;

    await store.appendReview(review);

    const latest = await store.latestReview("run-1");
    expect(latest?.resultMarkdown).toBe("Completed the requested change.");
    expect(latest).toEqual(expect.objectContaining({ id: "review-1" }));
  });

  it("selects the latest completed turn instead of the latest appended review", async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), "aperture-store-"));
    tempDirs.push(dir);
    const store = new EventStore(dir);
    const base = {
      resultMarkdown: "Done",
      analysis: {
        mode: "model" as const,
        model: "test/model",
        durationMs: 1,
        error: null
      }
    };
    await store.appendEvent({
      id: "stop-new",
      source: "codex",
      runId: "run-new",
      turnId: "turn-new",
      timestamp: "2026-07-31T06:20:00.000Z",
      type: "assistant_stop",
      payload: {},
      parentEventId: null
    });
    await store.appendEvent({
      id: "stop-old",
      source: "codex",
      runId: "run-old",
      turnId: "turn-old",
      timestamp: "2026-07-31T06:10:00.000Z",
      type: "assistant_stop",
      payload: {},
      parentEventId: null
    });
    await store.appendReview({
      ...base,
      id: "review-new",
      runId: "run-new",
      turnId: "turn-new",
      generatedAt: "2026-07-31T06:30:00.000Z"
    });
    await store.appendReview({
      ...base,
      id: "review-old-appended-last",
      runId: "run-old",
      turnId: "turn-old",
      generatedAt: "2026-07-31T06:31:00.000Z"
    });

    const latest = await store.latestReview();
    expect(latest?.id).toBe("review-new");
    expect(latest?.sourceCompletedAt).toBe("2026-07-31T06:20:00.000Z");
  });

  it("backfills project metadata for legacy reviews from captured cwd", async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), "aperture-store-"));
    tempDirs.push(dir);
    const store = new EventStore(dir);
    await store.appendEvent({
      id: "project-event",
      source: "codex",
      runId: "run-project",
      turnId: "turn-project",
      timestamp: "2026-07-31T06:00:00.000Z",
      type: "assistant_stop",
      payload: { cwd: "/Users/example/Aperture" },
      parentEventId: null
    });
    await store.appendReview({
      id: "legacy-review",
      runId: "run-project",
      turnId: "turn-project",
      generatedAt: "2026-07-31T06:01:00.000Z",
      resultMarkdown: "Done",
      analysis: {
        mode: "model",
        model: "test/model",
        durationMs: 1,
        error: null
      }
    });

    const [review] = await store.listReviews("run-project");
    expect(review.projectName).toBe("Aperture");
    expect(review.projectPath).toBe("/Users/example/Aperture");
  });

  it("never persists credentials embedded in captured events", async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), "aperture-store-"));
    tempDirs.push(dir);
    const store = new EventStore(dir);
    await store.appendEvent({
      id: "secret-event",
      source: "codex",
      runId: "run-secret",
      turnId: "turn-secret",
      timestamp: "2026-07-31T06:00:00.000Z",
      type: "user_prompt",
      payload: {
        prompt: "key=sk-or-v1-fixture_secret_1234567890",
        apiKey: "another-sensitive-value"
      },
      parentEventId: null
    });

    const [stored] = await store.listEvents("run-secret");
    expect(JSON.stringify(stored)).not.toContain("fixture_secret");
    expect(stored.payload.apiKey).toBe("[REDACTED_SENSITIVE_VALUE]");
  });
});
