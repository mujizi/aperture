import {
  appendFile,
  chmod,
  mkdir,
  readFile,
  rename,
  writeFile
} from "node:fs/promises";
import path from "node:path";
import type { AgentEvent, ReviewSnapshot } from "../core/types.js";
import {
  redactSensitiveText,
  redactSensitiveValue
} from "./redaction.js";

const MAX_COMPLETION_CLOCK_DRIFT_MS = 5 * 60 * 1000;

async function readJsonLines<T>(filePath: string): Promise<T[]> {
  try {
    const content = await readFile(filePath, "utf8");
    return content
      .split("\n")
      .filter(Boolean)
      .flatMap((line) => {
        try {
          return [JSON.parse(line) as T];
        } catch {
          return [];
        }
      });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
}

export class EventStore {
  readonly dataDir: string;
  private readonly eventsPath: string;
  private readonly reviewsPath: string;
  private initPromise: Promise<void> | null = null;

  constructor(dataDir: string) {
    this.dataDir = dataDir;
    this.eventsPath = path.join(dataDir, "events.jsonl");
    this.reviewsPath = path.join(dataDir, "reviews.jsonl");
  }

  async init() {
    this.initPromise ??= this.prepare();
    await this.initPromise;
  }

  private async prepare() {
    await mkdir(this.dataDir, { recursive: true });
    await Promise.all(
      [this.eventsPath, this.reviewsPath].map(async (filePath) => {
        try {
          const current = await readFile(filePath, "utf8");
          const redacted = redactSensitiveText(current);
          if (redacted !== current) {
            const temporary = `${filePath}.redacting`;
            await writeFile(temporary, redacted, { encoding: "utf8", mode: 0o600 });
            await rename(temporary, filePath);
          }
          await chmod(filePath, 0o600);
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
        }
      })
    );
  }

  async appendEvent(event: AgentEvent) {
    await this.init();
    const safe = redactSensitiveValue(event) as AgentEvent;
    await appendFile(this.eventsPath, `${JSON.stringify(safe)}\n`, {
      encoding: "utf8",
      mode: 0o600
    });
    return safe;
  }

  async appendReview(review: ReviewSnapshot) {
    await this.init();
    const safe = redactSensitiveValue(review) as ReviewSnapshot;
    await appendFile(this.reviewsPath, `${JSON.stringify(safe)}\n`, {
      encoding: "utf8",
      mode: 0o600
    });
    return safe;
  }

  async listEvents(runId?: string, turnId?: string | null) {
    const events = await readJsonLines<AgentEvent>(this.eventsPath);
    return events.filter(
      (event) =>
        (!runId || event.runId === runId) &&
        (turnId === undefined || event.turnId === turnId)
    );
  }

  async listReviews(runId?: string) {
    const [reviews, events] = await Promise.all([
      readJsonLines<ReviewSnapshot>(this.reviewsPath),
      readJsonLines<AgentEvent>(this.eventsPath)
    ]);
    const projectByRun = new Map<string, { name: string; path: string }>();
    const projectByTurn = new Map<string, { name: string; path: string }>();
    for (const event of events) {
      const projectPath = String(event.payload.cwd ?? "").trim();
      if (!projectPath) continue;
      const project = {
        name: path.basename(path.resolve(projectPath)),
        path: projectPath
      };
      projectByRun.set(event.runId, project);
      if (event.turnId) {
        projectByTurn.set(`${event.runId}:${event.turnId}`, project);
      }
    }
    return reviews
      .filter((review) => !runId || review.runId === runId)
      .map((review) => {
        if (review.projectName && review.projectPath) return review;
        const project = review.turnId
          ? projectByTurn.get(`${review.runId}:${review.turnId}`) ??
            projectByRun.get(review.runId)
          : projectByRun.get(review.runId);
        return project
          ? {
              ...review,
              projectName: review.projectName ?? project.name,
              projectPath: review.projectPath ?? project.path
            }
          : review;
      });
  }

  async latestReview(runId?: string) {
    const [reviews, events] = await Promise.all([
      this.listReviews(runId),
      this.listEvents(runId)
    ]);
    const completionTimes = new Map<string, string>();
    for (const event of events) {
      if (event.type !== "assistant_stop" || !event.turnId) continue;
      completionTimes.set(`${event.runId}:${event.turnId}`, event.timestamp);
    }
    const completedAt = (review: ReviewSnapshot) => {
      const candidate = review.sourceCompletedAt ??
      (review.turnId
        ? completionTimes.get(`${review.runId}:${review.turnId}`)
        : undefined) ??
      review.generatedAt;
      const candidateTime = Date.parse(candidate);
      const generatedTime = Date.parse(review.generatedAt);
      if (
        !Number.isFinite(candidateTime) ||
        candidateTime > generatedTime + MAX_COMPLETION_CLOCK_DRIFT_MS
      ) {
        return review.generatedAt;
      }
      return candidate;
    };
    const latest = reviews.reduce<ReviewSnapshot | null>((current, candidate) => {
      if (!current) return candidate;
      return Date.parse(completedAt(candidate)) >= Date.parse(completedAt(current))
        ? candidate
        : current;
    }, null);
    if (!latest) return null;
    return {
      ...latest,
      sourceCompletedAt: completedAt(latest)
    };
  }
}
