// @vitest-environment jsdom

import { afterEach, describe, expect, it } from "vitest";
import { selectedReviewText } from "./CompanionApp";

afterEach(() => {
  window.getSelection()?.removeAllRanges();
  document.body.replaceChildren();
});

describe("selectedReviewText", () => {
  it("returns only the characters selected inside the review", () => {
    const review = document.createElement("article");
    review.textContent = "光圈里的几个字可以复制";
    document.body.appendChild(review);

    const range = document.createRange();
    range.setStart(review.firstChild!, 4);
    range.setEnd(review.firstChild!, 7);
    const selection = window.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(range);

    expect(selectedReviewText(review)).toBe("几个字");
  });

  it("ignores selections outside the displayed review", () => {
    const review = document.createElement("article");
    review.textContent = "光圈内容";
    const outside = document.createElement("p");
    outside.textContent = "其他内容";
    document.body.append(review, outside);

    const range = document.createRange();
    range.selectNodeContents(outside);
    const selection = window.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(range);

    expect(selectedReviewText(review)).toBeNull();
  });
});
