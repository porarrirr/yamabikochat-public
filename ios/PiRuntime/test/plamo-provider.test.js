import test from "node:test";
import assert from "node:assert/strict";
import { createModels, getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import { installPlamoProvider, plamoModels, plamoResolution, plamoPayload } from "../src/plamo-provider.js";

const contract = { npm: "@ai-sdk/openai-compatible", api: "https://api.platform.preferredai.jp/v1", shape: "chat-completions",
  reasoning: true, input: ["text"], contextWindow: 262144, maxTokens: 20480, toolCall: true };
const tools = [{ name: "lookup", description: "Look up a value", parameters: { type: "object", properties: {} } }];

for (const id of plamoModels) {
  for (const catalogContract of [undefined, contract]) test(`PLaMo official resolution: ${id}, catalog=${!!catalogContract}`, () => {
    const models = createModels();
    installPlamoProvider(models);
    const config = { provider: "plamo", model: id, catalogContract };
    for (const thinkingLevel of [undefined, "off", "medium"]) {
      const resolution = plamoResolution({ ...config, thinkingLevel }, models);
      assert.equal(resolution.supported, true);
      assert.equal(resolution.api, "openai-completions");
      assert.equal(resolution.contextWindow, 262144);
      assert.equal(resolution.maxTokens, 20480);
      assert.equal(resolution.toolCall, true);
      assert.deepEqual(getSupportedThinkingLevels(models.getModel("plamo", id)), ["off", "medium"]);
    }
  });

  for (const reasoning of ["off", "medium"]) test(`PLaMo Pi serializer, reasoning and usage: ${id}/${reasoning}`, async () => {
    const models = createModels();
    installPlamoProvider(models);
    let payload;
    const result = await models.streamSimple(models.getModel("plamo", id), {
      systemPrompt: "System", messages: [{ role: "user", content: "Hi", timestamp: 1 }], tools
    }, {
      apiKey: "test", reasoning,
      fetch: async (url, options) => {
        assert.equal(String(url), "https://api.platform.preferredai.jp/v1/chat/completions");
        assert.equal(new Headers(options.headers).get("authorization"), "Bearer test");
        payload = JSON.parse(options.body);
        return new Response('data: {"choices":[{"index":0,"delta":{"reasoning_content":"Thinking"},"finish_reason":null}]}\n\ndata: {"choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":"stop"}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}\n\ndata: [DONE]\n\n', { headers: { "content-type": "text/event-stream" } });
      }
    }).result();
    assert.equal(result.stopReason, "stop", result.errorMessage);
    assert.equal(result.content.find(part => part.type === "text")?.text, "hello");
    assert.equal(result.content.find(part => part.type === "thinking")?.thinking, "Thinking");
    assert.equal(result.usage.input, 5);
    assert.equal(result.usage.output, 3);
    assert.equal(payload.model, id);
    assert.equal(payload.max_tokens, 20480);
    assert.equal(payload.reasoning_effort, reasoning === "off" ? "none" : "medium");
    assert.equal(payload.messages[0].role, "system");
    assert.equal(payload.tools[0].function.name, "lookup");
    assert.equal(payload.stream_options.include_usage, true);
    for (const field of ["store", "max_completion_tokens", "prompt_cache_key", "web_search_options"]) assert.equal(payload[field], undefined);
  });
}

test("PLaMo rejects unknown models, conflicting contracts and unsupported effort without substitution", () => {
  const models = createModels();
  installPlamoProvider(models);
  const config = { provider: "plamo", model: "plamo-3.1-prime" };
  assert.equal(plamoResolution({ ...config, model: "unknown" }, models).reason, "pi_model_missing");
  assert.equal(plamoResolution({ ...config, model: "plamo-3.1-prime-deep-research" }, models).reason, "plamo_background_jobs_unsupported");
  for (const thinkingLevel of ["low", "high", "max"]) assert.equal(plamoResolution({ ...config, thinkingLevel }, models).reason, "plamo_reasoning_effort_unsupported");
  for (const [change, reason] of [[{ npm: "unknown" }, "catalog_contract_ambiguous"], [{ shape: "responses" }, "protocol_conflict"],
    [{ api: "https://other.example/v1" }, "endpoint_conflict"], [{ reasoning: false }, "catalog_contract_conflict"],
    [{ input: ["image"] }, "catalog_contract_conflict"], [{ contextWindow: 128000 }, "catalog_contract_conflict"],
    [{ maxTokens: 8000 }, "catalog_contract_conflict"], [{ toolCall: false }, "catalog_contract_conflict"]]) {
    assert.equal(plamoResolution({ ...config, catalogContract: { ...contract, ...change } }, models).reason, reason);
  }
});

test("PLaMo search uses a top-level option and removes every forbidden field from the Pi request", async () => {
  const models = createModels();
  installPlamoProvider(models);
  const config = { provider: "plamo", model: "plamo-3.1-prime" };
  const request = { tools: [{ type: "plamo_web_search", payload: {} }] };
  let payload;
  const result = await models.streamSimple(models.getModel("plamo", config.model), {
    messages: [{ role: "user", content: "Search", timestamp: 1 }], tools
  }, {
    apiKey: "test", reasoning: "medium", temperature: 0.3, toolChoice: "auto",
    onPayload: value => plamoPayload(value, request, config),
    fetch: async (_url, options) => {
      payload = JSON.parse(options.body);
      return new Response('data: {"choices":[{"index":0,"delta":{"content":"[Source](https://example.com)"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n', { headers: { "content-type": "text/event-stream" } });
    }
  }).result();
  assert.equal(result.stopReason, "stop", result.errorMessage);
  assert.equal(result.content.find(part => part.type === "text")?.text, "[Source](https://example.com)");
  assert.deepEqual(payload.web_search_options, {});
  assert.equal(payload.reasoning_effort, "medium");
  for (const field of ["tools", "tool_choice", "temperature", "top_p", "presence_penalty", "frequency_penalty", "seed", "n", "stop", "logprobs"]) {
    assert.equal(payload[field], undefined, field);
    assert.equal(plamoPayload({ [field]: "forbidden" }, request, config)[field], undefined, field);
  }
  assert.throws(() => plamoPayload({}, request, { ...config, model: "plamo-3.0-prime" }), /plamo_web_search_unsupported/);
  assert.throws(() => plamoPayload({}, { tools: [{ type: "google_search" }] }, config), /plamo_native_tool_unsupported/);
});
