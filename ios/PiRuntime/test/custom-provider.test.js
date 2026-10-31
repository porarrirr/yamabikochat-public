import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { createModels, getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import { customProviderResolution, customStreamOptions, CUSTOM_PROVIDER } from "../src/custom-provider.js";
import { installSarashinaProvider, sarashinaResolution, sarashinaModels, sarashinaResponseFailure } from "../src/sarashina-provider.js";
const endpoint = (protocol = "openai-completions") => ({ name: "Test", protocol, modelId: "custom-model", baseUrl: "https://custom.example/v1", contextWindow: 128000, maxTokens: 4096, reasoning: true, toolCall: true, vision: false, reasoningEffort: "high", maxTokensField: "max_tokens", supportsStore: false, supportsDeveloperRole: false, supportsUsageInStreaming: false, temperature: 0.3 });
const configFor = (customEndpoint) => ({ provider: CUSTOM_PROVIDER, model: customEndpoint.modelId, customEndpoint, thinkingLevel: customEndpoint.reasoningEffort });
const sse = (data) => new Response(data, { headers: { "content-type": "text/event-stream" } });
const chatSSE = 'data: {"choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":"stop"}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":1,"total_tokens":6}}\n\ndata: [DONE]\n\n';
const anthropicSSE = 'event: message_start\ndata: {"type":"message_start","message":{"id":"msg_test","type":"message","role":"assistant","content":[],"model":"custom-model","usage":{"input_tokens":5,"output_tokens":0}}}\n\nevent: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello"}}\n\nevent: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\nevent: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n';
const responsesSSE = 'data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_test","type":"message","role":"assistant","content":[]}}\n\ndata: {"type":"response.content_part.added","item_id":"msg_test","output_index":0,"content_index":0,"part":{"type":"output_text","text":""}}\n\ndata: {"type":"response.output_text.delta","item_id":"msg_test","output_index":0,"content_index":0,"delta":"hello"}\n\ndata: {"type":"response.completed","response":{"id":"resp_test","status":"completed","output":[],"usage":{"input_tokens":5,"output_tokens":1,"total_tokens":6}}}\n\n';
for (const protocol of ["anthropic-messages", "openai-completions", "openai-responses", "mistral-conversations"]) test(`custom endpoint uses Pi ${protocol} serializer and parser`, async () => {
  const models = createModels(), custom = endpoint(protocol);
  if (protocol === "anthropic-messages") custom.thinkingBudget = 2048;
  if (protocol === "mistral-conversations") custom.baseUrl = "https://custom.example/proxy";
  const config = configFor(custom), resolution = customProviderResolution(config, models);
  assert.equal(resolution.supported, true); assert.equal(resolution.api, protocol);
  const model = models.getModel(resolution.provider, resolution.model);
  let body, url, headers;
  const fetch = async (input, options) => { url = String(input); headers = new Headers(options.headers); body = JSON.parse(options.body); return sse(protocol === "anthropic-messages" ? anthropicSSE : protocol === "openai-responses" ? responsesSSE : chatSSE); };
  const result = await models.streamSimple(model, { messages: [{ role: "user", content: "Hi", timestamp: 1 }] }, {
    apiKey: "test-key", fetch, reasoning: "high", ...customStreamOptions({ ...config, catalogProvider: CUSTOM_PROVIDER, provider: resolution.provider })
  }).result();
  assert.equal(result.stopReason, "stop", result.errorMessage); assert.equal(result.content.find((part) => part.type === "text")?.text, "hello");
  assert.equal(body.model, "custom-model");
  if (protocol !== "anthropic-messages") assert.equal(body.temperature, 0.3);
  else assert.equal(body.temperature, undefined);
  if (protocol === "openai-completions") {
    assert.equal(url, "https://custom.example/v1/chat/completions"); assert.equal(body.max_tokens, 4096); assert.equal(body.reasoning_effort, "high"); assert.equal(body.store, undefined); assert.equal(body.stream_options, undefined);
  } else if (protocol === "openai-responses") {
    assert.equal(url, "https://custom.example/v1/responses"); assert.equal(body.max_output_tokens, 4096); assert.equal(body.reasoning.effort, "high");
  } else if (protocol === "mistral-conversations") {
    assert.equal(url, "https://custom.example/proxy/v1/chat/completions");
    assert.equal(headers.get("authorization"), "Bearer test-key");
    assert.equal(body.max_tokens, 4096);
    assert.equal(body.reasoning_effort, "high");
    assert.equal(body.messages[0].content, "Hi");
    assert.equal(result.usage.input, 5);
    assert.equal(result.usage.output, 1);
    for (const field of ["store", "stream_options", "max_completion_tokens"]) assert.equal(body[field], undefined);
  } else assert.equal(body.thinking.budget_tokens, 2048);
});
test("custom settings reject incomplete, invalid and mismatched configurations without fallback", () => {
  const models = createModels();
  for (const [change, reason] of [[{ protocol: "" }, "custom_protocol_required"], [{ protocol: "guess" }, "custom_protocol_required"], [{ baseUrl: "file:///tmp/model" }, "custom_base_url_invalid"], [{ baseUrl: "https://user:pass@example.com" }, "custom_base_url_invalid"], [{ maxTokens: 0 }, "custom_token_limits_invalid"], [{ maxTokens: 200000 }, "custom_token_limits_invalid"], [{ reasoning: false }, "custom_reasoning_invalid"], [{ temperature: 3 }, "custom_temperature_invalid"], [{ thinkingBudget: 1024 }, "custom_thinking_budget_invalid"]]) assert.equal(customProviderResolution(configFor({ ...endpoint(), ...change }), models).reason, reason);
  assert.equal(customProviderResolution({ ...configFor(endpoint()), model: "other" }, models).reason, "custom_model_mismatch");
  assert.equal(models.getProviders().length, 0);
});
test("changing endpoint cannot replace an active custom model; extended efforts remain explicit", () => {
  const models = createModels();
  const first = customProviderResolution(configFor(endpoint()), models), second = customProviderResolution(configFor({ ...endpoint(), baseUrl: "https://other.example/v1" }), models);
  assert.notEqual(first.provider, second.provider); assert.equal(models.getModel(first.provider, first.model).baseUrl, "https://custom.example/v1");
  for (const effort of ["xhigh", "max"]) { const result = customProviderResolution(configFor({ ...endpoint(), reasoningEffort: effort }), models); assert.equal(models.getModel(result.provider, result.model).thinkingLevelMap[effort], effort); }
});
for (const { id, contextWindow, toolCall, reasoning } of sarashinaModels) test(`official Sarashina contract and payload: ${id}`, async () => {
  const models = createModels(); installSarashinaProvider(models);
  for (const catalogContract of [undefined, { npm: "@ai-sdk/openai-compatible", api: "https://api.sarashina.ai/v1", shape: "chat-completions", toolCall }]) {
    const resolution = sarashinaResolution({ provider: "sarashina", model: id, catalogContract }, models);
    assert.equal(resolution.supported, true); assert.equal(resolution.contextWindow, contextWindow); assert.equal(resolution.maxTokens, 8000); assert.equal(resolution.toolCall, toolCall); assert.equal(resolution.reasoning, reasoning);
  }
  let payload;
  const result = await models.streamSimple(models.getModel("sarashina", id), { systemPrompt: "System", messages: [{ role: "user", content: "Hi", timestamp: 1 }] }, { apiKey: "test", fetch: async (url, options) => { assert.equal(String(url), "https://api.sarashina.ai/v1/chat/completions"); payload = JSON.parse(options.body); return sse(chatSSE); } }).result();
  assert.equal(result.stopReason, "stop", result.errorMessage); assert.equal(result.usage.input, 5); assert.equal(payload.max_completion_tokens, 8000);
  for (const field of ["store", "stream_options", "reasoning_effort", "prompt_cache_key"]) assert.equal(payload[field], undefined);
  assert.equal(payload.messages[0].role, "system");
});
test("Sarashina rejects unknown models, protocol and endpoint overrides", () => {
  const models = createModels(); installSarashinaProvider(models);
  assert.equal(sarashinaResolution({ provider: "sarashina", model: "unknown" }, models).reason, "pi_model_missing");
  for (const [catalogContract, reason] of [[{ shape: "responses" }, "protocol_conflict"], [{ api: "https://other.example/v1" }, "endpoint_conflict"], [{ npm: "unknown" }, "catalog_contract_ambiguous"], [{ reasoning: true }, "catalog_contract_conflict"], [{ maxTokens: 99999 }, "catalog_contract_conflict"]]) assert.equal(sarashinaResolution({ provider: "sarashina", model: "sarashina3-mini", catalogContract }, models).reason, reason);
});

// Exercise the Pi Google adapter's SDK transport against a local HTTP endpoint.
test("custom Gemini endpoint uses Pi Google serializer, authentication and stream parser", async (context) => {
  let body, path, apiKey;
  const server = createServer(async (request, response) => {
    path = request.url;
    apiKey = request.headers["x-goog-api-key"];
    let data = "";
    for await (const chunk of request) data += chunk;
    body = JSON.parse(data);
    response.writeHead(200, { "content-type": "text/event-stream" });
    response.end('data: {"candidates":[{"content":{"role":"model","parts":[{"text":"hello"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":1,"totalTokenCount":6}}\n\n');
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  context.after(() => { server.closeAllConnections(); server.close(); });
  const custom = { ...endpoint("google-generative-ai"), baseUrl: `http://127.0.0.1:${server.address().port}/v1beta` };
  const models = createModels(), config = configFor(custom);
  const resolution = customProviderResolution(config, models);
  assert.equal(resolution.supported, true);
  assert.equal(resolution.api, "google-generative-ai");
  const result = await models.streamSimple(models.getModel(resolution.provider, resolution.model), {
    messages: [{ role: "user", content: "Hi", timestamp: 1 }]
  }, { apiKey: "test-key", reasoning: "high", ...customStreamOptions(config) }).result();
  assert.equal(result.stopReason, "stop", result.errorMessage);
  assert.equal(result.content.find(part => part.type === "text")?.text, "hello");
  assert.equal(result.usage.input, 5);
  assert.equal(result.usage.output, 1);
  assert.equal(path, "/v1beta/models/custom-model:streamGenerateContent?alt=sse");
  assert.equal(apiKey, "test-key");
  assert.equal(body.contents[0].parts[0].text, "Hi");
  assert.equal(body.generationConfig.maxOutputTokens, 4096);
  assert.equal(body.generationConfig.temperature, 0.3);
  assert.equal(body.model, undefined);
});

test("custom Mistral stream failure does not retry another protocol or endpoint", async () => {
  const models = createModels(), config = configFor(endpoint("mistral-conversations"));
  const resolution = customProviderResolution(config, models);
  let requests = 0;
  const result = await models.streamSimple(models.getModel(resolution.provider, resolution.model), {
    messages: [{ role: "user", content: "Hi", timestamp: 1 }]
  }, { apiKey: "test-key", fetch: async () => {
    requests++;
    return new Response('{"message":"Invalid API key"}', { status: 401 });
  } }).result();
  assert.equal(result.stopReason, "error");
  assert.match(result.errorMessage, /401/);
  assert.equal(requests, 1);
});

for (const effort of ["low", "medium", "high"]) test(`Sarashina encrypted thinking replay: ${effort}`, async () => {
  const models = createModels(); installSarashinaProvider(models);
  const id = "sarashina3.2-mini-thinking", model = models.getModel("sarashina", id);
  assert.deepEqual(getSupportedThinkingLevels(model), ["low", "medium", "high"]);
  assert.equal(sarashinaResolution({ provider: "sarashina", model: id, thinkingLevel: effort }, models).supported, true);
  const encrypted = 'data: {"choices":[{"index":0,"delta":{"reasoning":"Y2lw"},"finish_reason":null}]}\n\ndata: {"choices":[{"index":0,"delta":{"reasoning":"aGVy"},"finish_reason":null}]}\n\n';
  let payload;
  const options = { apiKey: "test", reasoning: effort, fetch: async (url, options) => {
    payload = JSON.parse(options.body); return sse(encrypted + chatSSE);
  }};
  const messages = [{ role: "user", content: "Hi", timestamp: 1 }];
  const stream = models.streamSimple(model, { messages }, options);
  const events = [];
  for await (const event of stream) events.push(event);
  const result = await stream.result();
  assert.equal(result.stopReason, "stop", result.errorMessage);
  assert.equal(payload.reasoning_effort, effort);
  assert.equal(payload.max_completion_tokens, 8000);
  assert.equal(result.content.find(part => part.type === "thinking").thinkingSignature, "Y2lwaGVy");
  assert.ok(!events.some(event => event.type === "thinking_delta"));
  assert.equal(result.content.find(part => part.type === "thinking").thinking, "");
  await models.streamSimple(model, { messages: [...messages, JSON.parse(JSON.stringify(result)), { role: "user", content: "Continue", timestamp: 2 }] }, options).result();
  assert.equal(payload.messages.find(message => message.role === "assistant").reasoning, "Y2lwaGVy");
  assert.equal(payload.messages.find(message => message.role === "assistant").content, "hello");
  const other = { ...result, provider: "other" };
  await models.streamSimple(model, { messages: [...messages, other] }, options).result();
  assert.equal(payload.messages.find(message => message.role === "assistant").reasoning, undefined);
});
test("Sarashina rejects unsupported efforts without clamping or fallback", () => {
  const models = createModels(); installSarashinaProvider(models);
  for (const { id, reasoning } of sarashinaModels) {
    for (const thinkingLevel of reasoning ? ["off", "minimal", "xhigh", "max"] : ["low", "medium", "high"]) {
      assert.equal(sarashinaResolution({ provider: "sarashina", model: id, thinkingLevel }, models).reason, "sarashina_reasoning_unsupported");
    }
  }
});

for (const { id, toolCall } of sarashinaModels.filter(model => model.toolCall)) test(`Sarashina tool stream uses Pi parser: ${id}`, async () => {
  const models = createModels(); installSarashinaProvider(models);
  let payload;
  const result = await models.streamSimple(models.getModel("sarashina", id), {
    messages: [{ role: "user", content: "weather", timestamp: 1 }],
    tools: [{ name: "weather", description: "Weather", parameters: { type: "object", properties: {} } }]
  }, { apiKey: "test", toolChoice: "auto", fetch: async (url, options) => {
    payload = JSON.parse(options.body);
    return sse('data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}\n\ndata: [DONE]\n\n');
  }}).result();
  assert.equal(result.stopReason, "toolUse", result.errorMessage);
  assert.equal(result.content.find(part => part.type === "toolCall").name, "weather");
  assert.equal(payload.tool_choice, "auto");
  assert.equal(payload.tools[0].function.name, "weather");
});

for (const { id, reasoning } of sarashinaModels) test(`Sarashina serializes iOS text blocks as strings: ${id}`, async () => {
  const models = createModels(); installSarashinaProvider(models);
  let payload;
  const result = await models.streamSimple(models.getModel("sarashina", id), {
    systemPrompt: "System",
    messages: [{ role: "user", content: [{ type: "text", text: "今日の天気を調べて" }, { type: "text", text: "東京" }], timestamp: 1 }],
    ...(id !== "sarashina3-guard" ? { tools: [{ name: "weather", description: "Weather", parameters: { type: "object", properties: {} } }] } : {})
  }, { apiKey: "test", ...(reasoning ? { reasoning: "high" } : {}), toolChoice: "auto", fetch: async (url, options) => {
    payload = JSON.parse(options.body);
    assert.ok(payload.messages.every(message => typeof message.content === "string"));
    return sse(chatSSE);
  }}).result();
  assert.equal(result.stopReason, "stop", result.errorMessage);
  assert.equal(payload.messages.find(message => message.role === "user").content, "今日の天気を調べて\n東京");
  if (reasoning) assert.equal(payload.reasoning_effort, "high");
});

test("Sarashina reports the provider output limit when thinking exhausts the budget before an answer", async () => {
  const models = createModels(); installSarashinaProvider(models);
  const result = await models.streamSimple(models.getModel("sarashina", "sarashina3.2-mini-thinking"), {
    messages: [{ role: "user", content: "Question", timestamp: 1 }]
  }, { apiKey: "test", reasoning: "high", fetch: async (url, options) => {
    assert.equal(JSON.parse(options.body).max_completion_tokens, 8000);
    return sse('data: {"choices":[{"index":0,"delta":{"reasoning":"Y2lwaGVy"},"finish_reason":"length"}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":1834,"completion_tokens":8000,"total_tokens":9834}}\n\ndata: [DONE]\n\n');
  }}).result();
  assert.equal(result.stopReason, "length");
  assert.equal(result.usage.output, 8000);
  const failure = sarashinaResponseFailure(result);
  assert.equal(failure.code, "sarashina_output_limit_before_answer");
  assert.match(failure.message, /Sarashina API.*8,000-token/);
  assert.match(failure.message, /low or medium/);
  assert.equal(result.content.find(part => part.type === "thinking").thinkingSignature, "Y2lwaGVy");
  assert.equal(sarashinaResponseFailure({ ...result, stopReason: "stop" }), null);
  assert.equal(sarashinaResponseFailure({ ...result, provider: "other" }), null);
  assert.equal(sarashinaResponseFailure({ ...result, content: [{ type: "text", text: "Partial answer" }] }), null);
  assert.equal(sarashinaResponseFailure({ ...result, content: [{ type: "toolCall", id: "call", name: "test", arguments: {} }] }), null);
});
