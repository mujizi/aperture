import type { ReviewSnapshot } from "../core/types";

const MAX_COMPLETION_CLOCK_DRIFT_MS = 5 * 60 * 1000;

function reviewKey(review: ReviewSnapshot) {
  return `${review.runId}:${review.turnId ?? "latest"}`;
}

function timestamp(value: string | undefined) {
  const parsed = Date.parse(value ?? "");
  return Number.isFinite(parsed) ? parsed : 0;
}

function completionTime(review: ReviewSnapshot) {
  const completed = timestamp(review.sourceCompletedAt ?? review.generatedAt);
  const generated = timestamp(review.generatedAt);
  return completed > generated + MAX_COMPLETION_CLOCK_DRIFT_MS
    ? generated
    : completed;
}

export function mergeReviewHistory(
  current: ReviewSnapshot[],
  incoming: ReviewSnapshot[]
) {
  const byTurn = new Map<string, ReviewSnapshot>();

  for (const review of [...current, ...incoming]) {
    const key = reviewKey(review);
    const existing = byTurn.get(key);
    if (
      !existing ||
      timestamp(review.generatedAt) >= timestamp(existing.generatedAt)
    ) {
      byTurn.set(key, review);
    }
  }

  return [...byTurn.values()].sort(
    (left, right) =>
      completionTime(left) - completionTime(right) ||
      timestamp(left.generatedAt) - timestamp(right.generatedAt)
  );
}
