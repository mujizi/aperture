import { X } from "lucide-react";
import {
  useEffect,
  useRef,
  useState
} from "react";
import type { ReviewSnapshot } from "../core/types";
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

function notifyNative(review: ReviewSnapshot | null, connected: boolean) {
  if (!window.webkit?.messageHandlers?.aperture) return;
  window.webkit.messageHandlers.aperture.postMessage({
    type: "review",
    connected,
    reviewId: review?.id ?? null
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
  const [reviewHistory, setReviewHistory] = useState<ReviewSnapshot[]>([]);
  const [historyOffset, setHistoryOffset] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const shellRef = useRef<HTMLElement | null>(null);
  const processingStartedAt = useRef(0);
  const completionTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
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

  useEffect(() => {
    void Promise.all([getCurrentReview(), getReviews()])
      .then(([{ review: current, monitoring: currentMonitoring }, history]) => {
        const reviews = mergeReviewHistory(
          history.reviews,
          current ? [current] : []
        );
        setMonitoringState(currentMonitoring.enabled);
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
    stream.onerror = () => notifyNative(review, false);

    return () => {
      stream.close();
      if (completionTimer.current) clearTimeout(completionTimer.current);
    };
    // The EventSource owns subsequent state transitions.
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
          <h1>已暂停</h1>
          <p>监控已关闭。</p>
        </section>
      )}

      {monitoring && phase === "waiting" && (
        <section className="minimal-status">
          <MinimalSignal processing={false} />
          <h1>等待</h1>
          <p>目前没有新的结果。</p>
        </section>
      )}

      {monitoring && phase === "processing" && (
        <section className="minimal-status">
          <MinimalSignal processing />
        </section>
      )}

      {monitoring && phase === "complete" && review && (
        <article className="markdown-result" aria-label="Aperture 处理结果">
          <section className="markdown-section markdown-answer">
            <AttentionMarkdown source={review.resultMarkdown} />
          </section>
        </article>
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
