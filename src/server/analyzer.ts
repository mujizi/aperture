import { randomUUID } from "node:crypto";
import type { AgentEvent, ReviewSnapshot } from "../core/types.js";
import { analyzeWithOpenRouter, type OpenRouterConfig } from "./openrouter.js";

function turnContext(events: AgentEvent[]) {
  const stopEvent = [...events]
    .reverse()
    .find((event) => event.type === "assistant_stop");
  const promptEvent = [...events]
    .reverse()
    .find((event) => event.type === "user_prompt");
  return {
    runId: stopEvent?.runId ?? events[0]?.runId ?? "unknown-session",
    turnId: stopEvent?.turnId ?? events.at(-1)?.turnId ?? null,
    goal: String(promptEvent?.payload.prompt ?? ""),
    completedAt: stopEvent?.timestamp ?? new Date().toISOString()
  };
}

function modelFailureReason(error: string | null, openRouter: OpenRouterConfig) {
  if (!openRouter.apiKey) return "OpenRouter API Key 尚未配置";
  if (!openRouter.model) return "分析模型尚未配置";
  if (/not available in your region/i.test(error ?? "")) {
    return `模型 ${openRouter.model} 在当前区域不可用`;
  }
  if (/abort|timeout|timed out/i.test(error ?? "")) return "模型调用超时";
  return error?.trim().slice(0, 240) || "模型没有返回可用结果";
}

function review(
  context: ReturnType<typeof turnContext>,
  resultMarkdown: string,
  openRouter: OpenRouterConfig,
  started: number,
  error: string | null
): ReviewSnapshot {
  return {
    id: randomUUID(),
    runId: context.runId,
    turnId: context.turnId,
    generatedAt: new Date().toISOString(),
    sourceCompletedAt: context.completedAt,
    resultMarkdown,
    analysis: {
      mode: error ? "error" : "model",
      model: openRouter.model ?? null,
      durationMs: Date.now() - started,
      error
    }
  };
}

export async function analyzeEvents(
  events: AgentEvent[],
  openRouter: OpenRouterConfig
): Promise<ReviewSnapshot> {
  const started = Date.now();
  const context = turnContext(events);
  try {
    const markdown = await analyzeWithOpenRouter(openRouter, {
      goal: context.goal,
      events
    });
    if (markdown) return review(context, markdown, openRouter, started, null);
    const reason = modelFailureReason(null, openRouter);
    return review(
      context,
      `模型调用失败，未生成本轮结果。\n\n${reason}。请在设置中检查或更换模型后重试。`,
      openRouter,
      started,
      reason
    );
  } catch (analysisError) {
    const error =
      analysisError instanceof Error
        ? analysisError.message
        : String(analysisError);
    const reason = modelFailureReason(error, openRouter);
    return review(
      context,
      `模型调用失败，未生成本轮结果。\n\n${reason}。请在设置中检查或更换模型后重试。`,
      openRouter,
      started,
      error
    );
  }
}
