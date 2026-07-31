const baseUrl = `http://127.0.0.1:${process.env.APERTURE_PORT ?? 4317}`;
const runId = `demo-${Date.now()}`;
const turnId = `turn-${Date.now()}`;
const cwd = process.cwd();

async function post(route: string, body: unknown) {
  const response = await fetch(`${baseUrl}${route}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!response.ok) throw new Error(`${route} failed: ${response.status} ${await response.text()}`);
  return response.json();
}

const common = {
  session_id: runId,
  turn_id: turnId,
  cwd,
  model: "demo/codex",
  permission_mode: "default"
};

await post("/api/events", {
  ...common,
  hook_event_name: "UserPromptSubmit",
  prompt: "把认证模块从客户端 token 迁移到服务端 session，保持旧移动端兼容，并完成验证。"
});

for (let index = 0; index < 12; index += 1) {
  await post("/api/events", {
    ...common,
    hook_event_name: "PostToolUse",
    tool_name: "read_file",
    tool_use_id: `demo-read-${index}`,
    tool_input: { path: `src/auth/context-${index}.ts` },
    tool_response: { content: `Existing auth context ${index}` }
  });
}

await post("/api/events", {
  ...common,
  hook_event_name: "PostToolUse",
  tool_name: "apply_patch",
  tool_use_id: "demo-tool-1",
  tool_input: {
    command:
      "*** Update File: src/auth/session.ts\n- validateClientToken(token)\n+ createServerSession(user)\n*** End Patch"
  },
  tool_response: "Updated src/auth/session.ts"
});

await post("/api/events", {
  ...common,
  hook_event_name: "PostToolUse",
  tool_name: "apply_patch",
  tool_use_id: "demo-tool-2",
  tool_input: {
    command:
      "*** Add File: migrations/20260731_create_sessions.sql\n+CREATE TABLE sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL);\n*** End Patch"
  },
  tool_response: "Added migrations/20260731_create_sessions.sql"
});

await post("/api/events", {
  ...common,
  hook_event_name: "PostToolUse",
  tool_name: "Bash",
  tool_use_id: "demo-tool-3",
  tool_input: { command: "npm test -- auth-integration" },
  tool_response: { exit_code: 0, output: "17 tests passed, 0 failed" }
});

await post("/api/events", {
  ...common,
  hook_event_name: "Stop",
  stop_hook_active: false,
  last_assistant_message:
    "认证模块已迁移到服务端 session，17 个集成测试通过。行为变化：旧版 token 校验路径已替换；生产 session 配置和旧移动端 token 兼容性尚未确认。"
});

const result = (await post("/api/analyze", { runId, turnId })) as {
  review: { analysis: { mode: string }; resultMarkdown: string };
};
console.log(
  `Demo review created in ${result.review.analysis.mode} mode at ${baseUrl}`
);

export {};
