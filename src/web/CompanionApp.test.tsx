// @vitest-environment jsdom

import { afterEach, describe, expect, it } from "vitest";
import type { ReviewSnapshot } from "../core/types";
import {
  displayedReviewMessage,
  reviewProjectName,
  selectedReviewText
} from "./CompanionApp";

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

describe("reviewProjectName", () => {
  const review = {
    id: "review",
    runId: "run",
    turnId: "turn",
    generatedAt: "2026-07-31T00:00:00.000Z",
    resultMarkdown: "result",
    analysis: { mode: "model", model: "test", durationMs: 1, error: null }
  } satisfies ReviewSnapshot;

  it("prefers the recorded project name", () => {
    expect(reviewProjectName({ ...review, projectName: "Aperture" })).toBe(
      "Aperture"
    );
  });

  it("falls back to the final project path component", () => {
    expect(
      reviewProjectName({ ...review, projectPath: "/Users/example/OtherProject" })
    ).toBe("OtherProject");
  });

  it("identifies the history page currently shown by the companion", () => {
    expect(
      displayedReviewMessage({
        ...review,
        id: "older-review",
        projectName: "Aperture"
      })
    ).toEqual({
      type: "displayedReview",
      reviewId: "older-review",
      projectName: "Aperture"
    });
  });
});
