import {
  appendFile,
  chmod,
  mkdir,
  readFile,
  rename,
  writeFile
} from "node:fs/promises";
import { createReadStream } from "node:fs";
import path from "node:path";
import { createInterface } from "node:readline";
import type { AgentEvent, ReviewSnapshot } from "../core/types.js";
import {
  redactSensitiveText,
  redactSensitiveValue
} from "./redaction.js";

const MAX_COMPLETION_CLOCK_DRIFT_MS = 5 * 60 * 1000;

async function* jsonLines<T>(filePath: string): AsyncGenerator<T> {
  const input = createReadStream(filePath, { encoding: "utf8" });
  const lines = createInterface({ input, crlfDelay: Infinity });
  try {
    for await (const line of lines) {
      if (!line) continue;
      try {
        yield JSON.parse(line) as T;
      } catch {
        // Keep reading when a partially written or invalid line is encountered.
      }
    }
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
    throw error;
  } finally {
    lines.close();
    input.destroy();
  }
}

async function readJsonLines<T>(
  filePath: string,
  predicate: (value: T) => boolean = () => true
): Promise<T[]> {
  const values: T[] = [];
  for await (const value of jsonLines<T>(filePath)) {
    if (predicate(value)) values.push(value);
  }
  return values;
}

async function findJsonLine<T>(
  filePath: string,
  predicate: (value: T) => boolean
): Promise<T | null> {
  for await (const value of jsonLines<T>(filePath)) {
    if (predicate(value)) return value;
  }
  return null;
}

interface EventProjection {
  projectByRun: Map<string, { name: string; path: string }>;
  projectByTurn: Map<string, { name: string; path: string }>;
  completionTimes: Map<string, string>;
}

function projectEvent(projection: EventProjection, event: AgentEvent) {
  const projectPath = String(event.payload.cwd ?? "").trim();
  if (projectPath) {
    const project = {
      name: path.basename(path.resolve(projectPath)),
      path: projectPath
    };
    projection.projectByRun.set(event.runId, project);
    if (event.turnId) {
      projection.projectByTurn.set(`${event.runId}:${event.turnId}`, project);
    }
  }
  if (event.type === "assistant_stop" && event.turnId) {
    projection.completionTimes.set(
      `${event.runId}:${event.turnId}`,
      event.timestamp
    );
  }
}

export class EventStore {
  readonly dataDir: string;
  private readonly eventsPath: string;
  private readonly reviewsPath: string;
  private initPromise: Promise<void> | null = null;
  private eventGeneration = 0;
  private eventProjectionCache: EventProjection | null = null;
  private eventProjectionPromise: Promise<EventProjection> | null = null;

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
    this.eventGeneration += 1;
    if (this.eventProjectionCache) {
      projectEvent(this.eventProjectionCache, safe);
    }
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
    return readJsonLines<AgentEvent>(
      this.eventsPath,
      (event) =>
        (!runId || event.runId === runId) &&
        (turnId === undefined || event.turnId === turnId)
    );
  }

  async findReview(reviewId: string) {
    return findJsonLine<ReviewSnapshot>(
      this.reviewsPath,
      (review) => review.id === reviewId
    );
  }

  private async eventProjection() {
    if (this.eventProjectionCache) return this.eventProjectionCache;
    if (this.eventProjectionPromise) return this.eventProjectionPromise;

    const generation = this.eventGeneration;
    const promise = (async () => {
      const projection: EventProjection = {
        projectByRun: new Map(),
        projectByTurn: new Map(),
        completionTimes: new Map()
      };
      for await (const event of jsonLines<AgentEvent>(this.eventsPath)) {
        projectEvent(projection, event);
      }
      if (generation === this.eventGeneration) {
        this.eventProjectionCache = projection;
      }
      return projection;
    })();
    this.eventProjectionPromise = promise;
    try {
      return await promise;
    } finally {
      if (this.eventProjectionPromise === promise) {
        this.eventProjectionPromise = null;
      }
    }
  }

  async listReviews(runId?: string) {
    const [reviews, projection] = await Promise.all([
      readJsonLines<ReviewSnapshot>(this.reviewsPath),
      this.eventProjection()
    ]);
    return reviews
      .filter((review) => !runId || review.runId === runId)
      .map((review) => {
        if (review.projectName && review.projectPath) return review;
        const project = review.turnId
          ? projection.projectByTurn.get(`${review.runId}:${review.turnId}`) ??
            projection.projectByRun.get(review.runId)
          : projection.projectByRun.get(review.runId);
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
    const [reviews, projection] = await Promise.all([
      this.listReviews(runId),
      this.eventProjection()
    ]);
    const completedAt = (review: ReviewSnapshot) => {
      const candidate = review.sourceCompletedAt ??
      (review.turnId
        ? projection.completionTimes.get(`${review.runId}:${review.turnId}`)
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
