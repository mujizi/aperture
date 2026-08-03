import { describe, expect, it } from "vitest";
import type { ReviewSnapshot } from "../core/types";
import {
  adjacentHistoryOffset,
  mergeReviewHistory,
  newestUnreadHistoryOffset
} from "./review-history";

function review(
  runId: string,
  turnId: string,
  completedAt: string,
  generatedAt = completedAt
) {
  return {
    id: `${runId}:${generatedAt}`,
    runId,
    turnId,
    generatedAt,
    sourceCompletedAt: completedAt,
    resultMarkdown: runId,
    analysis: {
      mode: "model",
      model: "test/model",
      durationMs: 1,
      error: null
    }
  } satisfies ReviewSnapshot;
}

describe("review history", () => {
  it("keeps sequential and interleaved tasks in completion order", () => {
    const first = review("first", "turn-1", "2026-07-31T08:00:00.000Z");
    const third = review("third", "turn-3", "2026-07-31T08:03:00.000Z");
    const second = review("second", "turn-2", "2026-07-31T08:05:00.000Z");

    expect(mergeReviewHistory([first], [third, second]).map((item) => item.runId))
      .toEqual(["first", "third", "second"]);
  });

  it("replaces a reanalysis of the same turn instead of adding a page", () => {
    const original = review(
      "task",
      "turn",
      "2026-07-31T08:00:00.000Z",
      "2026-07-31T08:01:00.000Z"
    );
    const reanalysis = review(
      "task",
      "turn",
      "2026-07-31T08:00:00.000Z",
      "2026-07-31T08:02:00.000Z"
    );

    expect(mergeReviewHistory([original], [reanalysis])).toEqual([reanalysis]);
  });

  it("does not let a future-dated preview replace the latest real page", () => {
    const preview = review(
      "preview",
      "preview-turn",
      "2026-08-01T12:00:00.000Z",
      "2026-08-01T06:00:00.000Z"
    );
    const real = review(
      "real",
      "real-turn",
      "2026-08-01T07:00:00.000Z",
      "2026-08-01T07:01:00.000Z"
    );

    expect(mergeReviewHistory([preview], [real]).map((item) => item.runId))
      .toEqual(["preview", "real"]);
  });

  it("opens the newest unread page and skips read pages while paging", () => {
    const reviews = [
      review("old-unread", "turn-1", "2026-08-01T07:00:00.000Z"),
      review("read-gap", "turn-2", "2026-08-01T08:00:00.000Z"),
      review("new-unread", "turn-3", "2026-08-01T09:00:00.000Z"),
      review("already-read", "turn-4", "2026-08-01T10:00:00.000Z")
    ];
    const unread = new Set([reviews[0].id, reviews[2].id]);
    const initialOffset = newestUnreadHistoryOffset(reviews, unread);

    expect(initialOffset).toBe(1);
    unread.delete(reviews[2].id);
    expect(adjacentHistoryOffset(reviews, initialOffset, "older", unread)).toBe(3);
  });
});
