import type { ReviewSnapshot } from "../core/types";

function reviewKey(review: ReviewSnapshot) {
  return `${review.runId}:${review.turnId ?? "latest"}`;
}

function timestamp(value: string | undefined) {
  const parsed = Date.parse(value ?? "");
  return Number.isFinite(parsed) ? parsed : 0;
}

function completionTime(review: ReviewSnapshot) {
  return timestamp(review.sourceCompletedAt ?? review.generatedAt);
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
