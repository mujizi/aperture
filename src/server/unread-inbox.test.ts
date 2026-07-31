import { describe, expect, it } from "vitest";
import {
  markInboxSeen,
  registerCompletedTurn,
  type UnreadInboxState
} from "./unread-inbox.js";

function inbox(): UnreadInboxState {
  return { unread: new Set(), counted: new Set() };
}

describe("unread answer inbox", () => {
  it("counts each completed turn once and clears only when viewed", () => {
    const state = inbox();
    expect(registerCompletedTurn(state, "run-1:turn-1")).toBe(true);
    expect(registerCompletedTurn(state, "run-2:turn-2")).toBe(true);
    expect(registerCompletedTurn(state, "run-3:turn-3")).toBe(true);
    expect(state.unread.size).toBe(3);

    markInboxSeen(state);
    expect(state.unread.size).toBe(0);
  });

  it("does not recount a focus or prompt reanalysis of the same turn", () => {
    const state = inbox();
    expect(registerCompletedTurn(state, "run-1:turn-1")).toBe(true);
    markInboxSeen(state);
    expect(registerCompletedTurn(state, "run-1:turn-1")).toBe(false);
    expect(state.unread.size).toBe(0);
  });
});
