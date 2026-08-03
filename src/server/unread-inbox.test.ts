import { describe, expect, it } from "vitest";
import {
  markInboxItemSeen,
  registerCompletedTurn,
  unreadReviewIds,
  type UnreadInboxState
} from "./unread-inbox.js";

function inbox(): UnreadInboxState {
  return { unread: new Set(), counted: new Set() };
}

describe("unread answer inbox", () => {
  it("counts each completed turn once and marks only the viewed turn as read", () => {
    const state = inbox();
    expect(registerCompletedTurn(state, "run-1:turn-1")).toBe(true);
    expect(registerCompletedTurn(state, "run-2:turn-2")).toBe(true);
    expect(registerCompletedTurn(state, "run-3:turn-3")).toBe(true);
    expect(state.unread.size).toBe(3);

    expect(markInboxItemSeen(state, "run-3:turn-3")).toBe(true);
    expect([...state.unread]).toEqual(["run-1:turn-1", "run-2:turn-2"]);
    expect(markInboxItemSeen(state, "run-3:turn-3")).toBe(false);
    expect(state.unread.size).toBe(2);
  });

  it("does not recount a focus or prompt reanalysis of the same turn", () => {
    const state = inbox();
    expect(registerCompletedTurn(state, "run-1:turn-1")).toBe(true);
    markInboxItemSeen(state, "run-1:turn-1");
    expect(registerCompletedTurn(state, "run-1:turn-1")).toBe(false);
    expect(state.unread.size).toBe(0);
  });

  it("maps unread turns to their latest review snapshot", () => {
    const reviews = [
      { id: "turn-1-old", runId: "run", turnId: "turn-1" },
      { id: "turn-2", runId: "run", turnId: "turn-2" },
      { id: "turn-1-latest", runId: "run", turnId: "turn-1" }
    ];

    expect(unreadReviewIds(reviews, new Set(["run:turn-1"]))).toEqual([
      "turn-1-latest"
    ]);
  });
});
