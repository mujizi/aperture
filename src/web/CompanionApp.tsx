import { Check, Copy, X } from "lucide-react";
import {
  useEffect,
  useRef,
  useState
} from "react";
import type { ReviewSnapshot } from "../core/types";
import { ApertureSceneView } from "./ApertureScene";
import { AttentionDocumentView } from "./AttentionDocument";
import { AttentionMarkdown } from "./AttentionMarkdown";
import { getCurrentReview, getReviews } from "./api";
import { mergeReviewHistory } from "./review-history";

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        aperture?: {
          postMessage: (message: Record<string, unknown>) => void;
        };
      };
    };
  }
}

type Phase = "waiting" | "processing" | "complete";
type CopyState = "idle" | "copied" | "failed";

async function copyReviewText(text: string) {
  const nativeHandler = window.webkit?.messageHandlers?.aperture;
  if (nativeHandler) {
    nativeHandler.postMessage({ type: "copy", text });
    return true;
  }

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    const copied = document.execCommand("copy");
    textarea.remove();
    return copied;
  } catch {
    return false;
  }
}

export function selectedReviewText(root: HTMLElement | null) {
  const selection = window.getSelection();
  if (
    !root ||
    !selection ||
    selection.isCollapsed ||
    !selection.anchorNode ||
    !selection.focusNode ||
    !root.contains(selection.anchorNode) ||
    !root.contains(selection.focusNode)
  ) {
    return null;
  }
  return selection.toString() || null;
}

export function reviewProjectName(review: ReviewSnapshot) {
  if (review.projectName?.trim()) return review.projectName.trim();
  const parts = review.projectPath?.split(/[\\/]/).filter(Boolean);
  return parts?.at(-1) ?? "未知工程";
}

function notifyNative(review: ReviewSnapshot | null, connected: boolean) {
  if (!window.webkit?.messageHandlers?.aperture) return;
  window.webkit.messageHandlers.aperture.postMessage({
    type: "review",
    connected,
    reviewId: review?.id ?? null,
    projectName: review ? reviewProjectName(review) : null
  });
}

function MinimalSignal({ processing }: { processing: boolean }) {
  return (
    <div className={processing ? "minimal-signal is-processing" : "minimal-signal"}>
      <span className="minimal-signal-orbit" />
      <span className="minimal-signal-ring" />
      <i />
      {processing && (
        <>
          <b className="minimal-scan minimal-scan--one" />
          <b className="minimal-scan minimal-scan--two" />
          <b className="minimal-scan minimal-scan--three" />
        </>
      )}
    </div>
  );
}

export function CompanionApp() {
  const [phase, setPhase] = useState<Phase>("waiting");
  const [monitoring, setMonitoringState] = useState(true);
  const [focusLevel, setFocusLevel] = useState(0.62);
  const [reviewHistory, setReviewHistory] = useState<ReviewSnapshot[]>([]);
  const [historyOffset, setHistoryOffset] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [copyState, setCopyState] = useState<CopyState>("idle");
  const shellRef = useRef<HTMLElement | null>(null);
  const reviewRef = useRef<HTMLElement | null>(null);
  const processingStartedAt = useRef(0);
  const completionTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const copyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const selectionAtCopyClick = useRef<string | null>(null);
  const review =
    reviewHistory[reviewHistory.length - 1 - historyOffset] ?? null;

  const beginProcessing = () => {
    if (completionTimer.current) clearTimeout(completionTimer.current);
    processingStartedAt.current = Date.now();
    setPhase("processing");
    window.webkit?.messageHandlers?.aperture?.postMessage({
      type: "phase",
      phase: "processing"
    });
  };

  const finishProcessing = (next: ReviewSnapshot) => {
    const elapsed = Date.now() - processingStartedAt.current;
    const delay = processingStartedAt.current ? Math.max(0, 900 - elapsed) : 0;
    if (completionTimer.current) clearTimeout(completionTimer.current);
    completionTimer.current = setTimeout(() => {
      setReviewHistory((current) => {
        const merged = mergeReviewHistory(current, [next]);
        notifyNative(merged.at(-1) ?? null, true);
        return merged;
      });
      setHistoryOffset(0);
      setPhase("complete");
      setError(null);
      window.webkit?.messageHandlers?.aperture?.postMessage({
        type: "phase",
        phase: "complete"
      });
    }, delay);
  };

  const copyReview = async () => {
    if (!review) return;
    if (copyTimer.current) clearTimeout(copyTimer.current);
    const copied = await copyReviewText(
      selectionAtCopyClick.current ??
        selectedReviewText(reviewRef.current) ??
        review.resultMarkdown
    );
    selectionAtCopyClick.current = null;
    setCopyState(copied ? "copied" : "failed");
    copyTimer.current = setTimeout(() => setCopyState("idle"), 1800);
  };

  useEffect(() => {
    void Promise.all([getCurrentReview(), getReviews()])
      .then(([{ review: current, monitoring: currentMonitoring, focus }, history]) => {
        const reviews = mergeReviewHistory(
          history.reviews,
          current ? [current] : []
        );
        setMonitoringState(currentMonitoring.enabled);
        setFocusLevel(focus.level);
        setReviewHistory(reviews);
        setHistoryOffset(0);
        setPhase(
          currentMonitoring.enabled && reviews.length ? "complete" : "waiting"
        );
        notifyNative(reviews.at(-1) ?? null, true);
      })
      .catch((loadError) => {
        setError(loadError instanceof Error ? loadError.message : String(loadError));
        setPhase("waiting");
        notifyNative(null, false);
      });

    const stream = new EventSource("/api/stream");
    stream.addEventListener("event", (event) => {
      const payload = JSON.parse((event as MessageEvent).data) as {
        type?: string;
      };
      if (payload.type === "assistant_stop" || payload.type === "analysis_started") {
        beginProcessing();
      }
    });
    stream.addEventListener("analysis", () => beginProcessing());
    stream.addEventListener("review", (event) => {
      finishProcessing(
        JSON.parse((event as MessageEvent).data) as ReviewSnapshot
      );
    });
    stream.addEventListener("monitoring", (event) => {
      const payload = JSON.parse((event as MessageEvent).data) as {
        enabled: boolean;
      };
      setMonitoringState(payload.enabled);
      setPhase("waiting");
    });
    stream.addEventListener("focus", (event) => {
      const payload = JSON.parse((event as MessageEvent).data) as {
        level: number;
      };
      setFocusLevel(payload.level);
    });
    stream.onerror = () => notifyNative(review, false);

    return () => {
      stream.close();
      if (completionTimer.current) clearTimeout(completionTimer.current);
      if (copyTimer.current) clearTimeout(copyTimer.current);
    };
    // The EventSource owns subsequent state transitions.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    setCopyState("idle");
    selectionAtCopyClick.current = null;
    if (copyTimer.current) clearTimeout(copyTimer.current);
  }, [review?.id]);

  useEffect(() => {
    const copySelection = (event: ClipboardEvent) => {
      const text = selectedReviewText(reviewRef.current);
      const nativeHandler = window.webkit?.messageHandlers?.aperture;
      if (!text || !nativeHandler) return;
      event.preventDefault();
      nativeHandler.postMessage({ type: "copy", text });
    };
    const copySelectionShortcut = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== "c") {
        return;
      }
      const text = selectedReviewText(reviewRef.current);
      const nativeHandler = window.webkit?.messageHandlers?.aperture;
      if (!text || !nativeHandler) return;
      event.preventDefault();
      nativeHandler.postMessage({ type: "copy", text });
    };

    document.addEventListener("copy", copySelection);
    window.addEventListener("keydown", copySelectionShortcut);
    return () => {
      document.removeEventListener("copy", copySelection);
      window.removeEventListener("keydown", copySelectionShortcut);
    };
  }, []);

  useEffect(() => {
    const turnPage = (event: KeyboardEvent) => {
      if (
        event.defaultPrevented ||
        event.metaKey ||
        event.ctrlKey ||
        event.altKey ||
        event.shiftKey
      ) {
        return;
      }
      const target = event.target;
      if (
        target instanceof HTMLElement &&
        (target.isContentEditable ||
          target.matches("input, textarea, select"))
      ) {
        return;
      }

      if (event.key === "ArrowLeft" && historyOffset < reviewHistory.length - 1) {
        event.preventDefault();
        setHistoryOffset((current) =>
          Math.min(reviewHistory.length - 1, current + 1)
        );
        shellRef.current?.scrollTo({ top: 0, behavior: "auto" });
      }
      if (event.key === "ArrowRight" && historyOffset > 0) {
        event.preventDefault();
        setHistoryOffset((current) => Math.max(0, current - 1));
        shellRef.current?.scrollTo({ top: 0, behavior: "auto" });
      }
    };

    window.addEventListener("keydown", turnPage);
    return () => window.removeEventListener("keydown", turnPage);
  }, [historyOffset, reviewHistory.length]);

  return (
    <main className="minimal-shell" ref={shellRef}>
      {!monitoring && (
        <section className="minimal-status">
          <MinimalSignal processing={false} />
          <h1 lang="en">paused</h1>
        </section>
      )}

      {monitoring && phase === "waiting" && (
        <section className="minimal-status">
          <MinimalSignal processing={false} />
          <h1 lang="en">wait</h1>
        </section>
      )}

      {monitoring && phase === "processing" && (
        <section className="minimal-status">
          <MinimalSignal processing />
        </section>
      )}

      {monitoring && phase === "complete" && review && (
        <>
          <article
            className="markdown-result"
            aria-label="Aperture 处理结果"
            ref={reviewRef}
          >
            <section className="markdown-section markdown-answer">
              {review.attentionScene ? (
                <ApertureSceneView
                  scene={review.attentionScene}
                  focusLevel={focusLevel}
                />
              ) : review.attentionDocument ? (
                <AttentionDocumentView
                  document={review.attentionDocument}
                  focusLevel={focusLevel}
                />
              ) : (
                <AttentionMarkdown source={review.resultMarkdown} />
              )}
            </section>
          </article>
          <button
            aria-label={copyState === "copied" ? "已复制" : "复制选中内容或全部内容"}
            className={`minimal-copy-button minimal-copy-button--${copyState}`}
            onMouseDown={() => {
              selectionAtCopyClick.current = selectedReviewText(reviewRef.current);
            }}
            onClick={() => void copyReview()}
            title="复制选中内容或全部内容"
            type="button"
          >
            {copyState === "copied" ? <Check size={14} /> : <Copy size={14} />}
          </button>
        </>
      )}

      {error && (
        <button className="minimal-error" onClick={() => setError(null)}>
          {error}
          <X size={12} />
        </button>
      )}
    </main>
  );
}
