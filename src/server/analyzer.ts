import { randomUUID } from "node:crypto";
import path from "node:path";
import type { AgentEvent, ReviewSnapshot } from "../core/types.js";
import { cleanQuestion } from "./events.js";
import { analyzeWithOpenRouter, type OpenRouterConfig } from "./openrouter.js";

function turnContext(events: AgentEvent[]) {
  const stopEvent = [...events]
    .reverse()
    .find(
      (event) =>
        event.type === "assistant_stop" &&
        String(event.payload.last_assistant_message ?? "").trim()
    );
  const promptEvents = events.filter((event) => event.type === "user_prompt");
  const promptEvent = promptEvents.at(-1);
  const seenQuestions = new Set<string>();
  const questions = promptEvents.flatMap((event) => {
    const question = cleanQuestion(String(event.payload.prompt ?? ""));
    if (!question || seenQuestions.has(question)) return [];
    seenQuestions.add(question);
    return [question];
  });
  const sessionEvent = [...events]
    .reverse()
    .find((event) => event.type === "session_start");
  const projectPath = String(
    stopEvent?.payload.cwd ??
      promptEvent?.payload.cwd ??
      sessionEvent?.payload.cwd ??
      ""
  ).trim();
  return {
    runId: stopEvent?.runId ?? events[0]?.runId ?? "unknown-session",
    turnId: stopEvent?.turnId ?? events.at(-1)?.turnId ?? null,
    question: questions.join("\n\n"),
    answer: String(stopEvent?.payload.last_assistant_message ?? "").trim(),
    completedAt: stopEvent?.timestamp ?? new Date().toISOString(),
    projectName: projectPath ? path.basename(path.resolve(projectPath)) : undefined,
    projectPath: projectPath || undefined
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
    projectName: context.projectName,
    projectPath: context.projectPath,
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
      question: context.question,
      answer: context.answer
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
