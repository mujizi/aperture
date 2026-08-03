import type { ReviewSnapshot } from "../core/types.js";

export interface UnreadInboxState {
  unread: Set<string>;
  counted: Set<string>;
}

export function reviewTurnKey(runId: string, turnId: string | null) {
  return `${runId}:${turnId ?? "latest"}`;
}

export function unreadReviewIds(
  reviews: Pick<ReviewSnapshot, "id" | "runId" | "turnId">[],
  unreadTurnKeys: Set<string>
) {
  const latestReviewByTurn = new Map<string, string>();
  for (const review of reviews) {
    const turnKey = reviewTurnKey(review.runId, review.turnId);
    if (unreadTurnKeys.has(turnKey)) {
      latestReviewByTurn.set(turnKey, review.id);
    }
  }
  return [...latestReviewByTurn.values()];
}

function trimSet(values: Set<string>, maximum: number) {
  while (values.size > maximum) {
    const oldest = values.values().next().value;
    if (typeof oldest !== "string") break;
    values.delete(oldest);
  }
}

export function registerCompletedTurn(
  state: UnreadInboxState,
  turnKey: string
) {
  if (state.counted.has(turnKey)) return false;
  state.counted.add(turnKey);
  state.unread.add(turnKey);
  trimSet(state.counted, 500);
  trimSet(state.unread, 99);
  return true;
}

export function markInboxItemSeen(
  state: UnreadInboxState,
  turnKey: string
) {
  return state.unread.delete(turnKey);
}
