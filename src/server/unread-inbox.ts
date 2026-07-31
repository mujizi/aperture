export interface UnreadInboxState {
  unread: Set<string>;
  counted: Set<string>;
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

export function markInboxSeen(state: UnreadInboxState) {
  state.unread.clear();
}
