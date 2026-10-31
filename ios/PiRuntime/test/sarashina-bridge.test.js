import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

test("Sarashina thinking-only length termination is a failed bridge run with usage and recovery guidance", { timeout: 15_000 }, async t => {
  const probe = createServer();
  await new Promise(resolve => probe.listen(0, "127.0.0.1", resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yamabiko-sarashina-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const mock = path.join(root, "transport.mjs"), requests = path.join(root, "requests.jsonl");
  const sse = 'data: {"choices":[{"index":0,"delta":{"reasoning":"Y2lwaGVy"},"finish_reason":"length"}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":1834,"completion_tokens":8000,"total_tokens":9834}}\n\ndata: [DONE]\n\n';
  fs.writeFileSync(mock, `
    import fs from "node:fs";
    globalThis.fetch = async (url, options) => {
      if (String(url) !== "https://api.sarashina.ai/v1/chat/completions") throw new Error("Unexpected test endpoint");
      fs.appendFileSync(${JSON.stringify(requests)}, options.body + "\\n");
      return new Response(${JSON.stringify(sse)}, { headers: { "content-type": "text/event-stream" } });
    };
  `);
  const child = spawn(process.execPath, ["--import", mock, new URL("../bundle/main.js", import.meta.url).pathname, String(port), "sarashina-limit-test"], { stdio: "ignore" });
  t.after(() => child.kill());
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: "Bearer sarashina-limit-test", "content-type": "application/json" };
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(base + "/health", { headers })).ok) break; } catch {}
    assert.ok(attempt < 200, "runtime did not start");
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  const response = await fetch(base + "/v1/run", { method: "POST", headers, body: JSON.stringify({
    runId: "sarashina-output-limit",
    config: { contractVersion: 2, provider: "sarashina", model: "sarashina3.2-mini-thinking", apiKey: "test-key", thinkingLevel: "high" },
    request: { messages: [{ role: "user", content: "Question", attachments: [] }], tools: [], metadata: {} }
  }) });
  const events = (await response.text()).trim().split("\n").map(line => JSON.parse(line));
  const end = events.find(event => event.type === "llm_end");
  assert.equal(end.succeeded, false);
  assert.equal(end.usage.outputTokens, 8000);
  assert.equal(end.usage.inputTokens, 1834);
  assert.ok(!events.some(event => event.type === "completed" || event.type === "reasoning_delta"));
  const failure = events.find(event => event.type === "error");
  assert.equal(failure.errorCode, "SARASHINA_OUTPUT_LIMIT_BEFORE_ANSWER");
  assert.match(failure.message, /Sarashina API.*8,000-token/);
  const snapshot = events.find(event => event.type === "execution_snapshot").execution;
  assert.equal(snapshot.failure.code, "sarashina_output_limit_before_answer");
  assert.equal(snapshot.state.lastStopReason, "length");
  const calls = fs.readFileSync(requests, "utf8").trim().split("\n").map(line => JSON.parse(line));
  assert.equal(calls.length, 1, "must not automatically retry or change effort");
  assert.equal(calls[0].reasoning_effort, "high");
  assert.equal(calls[0].max_completion_tokens, 8000);
});
