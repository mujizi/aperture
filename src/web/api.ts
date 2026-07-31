import type { ReviewSnapshot } from "../core/types";

async function json<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, init);
  const payload = (await response.json()) as T & { error?: string };
  if (!response.ok) throw new Error(payload.error || `Request failed (${response.status})`);
  return payload;
}

export async function getCurrentReview() {
  return json<{
    review: ReviewSnapshot | null;
    monitoring: { enabled: boolean };
    focus: { level: number };
  }>("/api/review/current");
}

export async function getReviews() {
  return json<{ reviews: ReviewSnapshot[] }>("/api/reviews");
}

export async function getConfig() {
  return json<{
    openRouter: { enabled: boolean; model: string | null };
    monitoring: { enabled: boolean };
    focus: { level: number };
    port: number;
    dataDir: string;
  }>("/api/config");
}

export async function setMonitoring(enabled: boolean) {
  return json<{ monitoring: { enabled: boolean } }>("/api/monitoring", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ enabled })
  });
}

export async function setFocusLevel(level: number) {
  return json<{ focus: { level: number } }>("/api/focus", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ level })
  });
}

export async function saveConfig(input: { model: string; apiKey: string }) {
  return json<{
    openRouter: { enabled: boolean; model: string | null };
    port: number;
    dataDir: string;
  }>("/api/config", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input)
  });
}
