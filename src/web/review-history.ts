import type { ReviewSnapshot } from "../core/types";

const MAX_COMPLETION_CLOCK_DRIFT_MS = 5 * 60 * 1000;

function reviewKey(review: ReviewSnapshot) {
  return `${review.runId}:${review.turnId ?? "latest"}`;
}

export interface ReviewProjectSummary {
  key: string;
  name: string;
  path: string | null;
  unreadCount: number;
}

export function reviewProjectKey(review: ReviewSnapshot) {
  const projectPath = review.projectPath?.trim();
  if (projectPath) return projectPath;
  const projectName = review.projectName?.trim();
  return projectName ? `name:${projectName}` : null;
}

export function filterReviewHistory(
  reviews: ReviewSnapshot[],
  projectKey: string | null
) {
  if (!projectKey) return reviews;
  return reviews.filter((review) => reviewProjectKey(review) === projectKey);
}

export function reviewProjectCatalog(
  reviews: ReviewSnapshot[],
  unreadReviewIds: ReadonlySet<string>
) {
  const projects = new Map<string, ReviewProjectSummary & { order: number }>();
  reviews.forEach((review, order) => {
    const key = reviewProjectKey(review);
    const name = review.projectName?.trim();
    if (!key || !name) return;
    const existing = projects.get(key);
    projects.set(key, {
      key,
      name,
      path: review.projectPath?.trim() || null,
      unreadCount:
        (existing?.unreadCount ?? 0) +
        (unreadReviewIds.has(review.id) ? 1 : 0),
      order
    });
  });
  return [...projects.values()]
    .sort((left, right) => right.order - left.order)
    .map(({ order: _order, ...project }) => project);
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

export function newestUnreadHistoryOffset(
  reviews: ReviewSnapshot[],
  unreadReviewIds: ReadonlySet<string>
) {
  for (let index = reviews.length - 1; index >= 0; index -= 1) {
    if (unreadReviewIds.has(reviews[index].id)) {
      return reviews.length - 1 - index;
    }
  }
  return 0;
}

export function adjacentHistoryOffset(
  reviews: ReviewSnapshot[],
  currentOffset: number,
  direction: "older" | "newer",
  unreadReviewIds: ReadonlySet<string>
) {
  const currentIndex = reviews.length - 1 - currentOffset;
  const step = direction === "older" ? -1 : 1;
  for (
    let index = currentIndex + step;
    index >= 0 && index < reviews.length;
    index += step
  ) {
    if (unreadReviewIds.has(reviews[index].id)) {
      return reviews.length - 1 - index;
    }
  }
  return direction === "older"
    ? Math.min(reviews.length - 1, currentOffset + 1)
    : Math.max(0, currentOffset - 1);
}
