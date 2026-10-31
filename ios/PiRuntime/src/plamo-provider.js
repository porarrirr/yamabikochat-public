// Official contract: https://docs.plamo.preferredai.jp/ja/api
// Drift check: scripts/check-plamo-contract.py
import { createProvider, envApiKeyAuth } from "@earendil-works/pi-ai";
import { stream, streamSimple } from "@earendil-works/pi-ai/api/openai-completions";

export const plamoModels = ["plamo-3.0-prime", "plamo-3.1-prime"];

export function installPlamoProvider(models) {
  models.setProvider(createProvider({
    id: "plamo", name: "PLaMo",
    auth: { apiKey: envApiKeyAuth("PLaMo API key", ["PLAMO_API_KEY"]) },
    models: plamoModels.map(id => ({
      id, name: id, provider: "plamo", api: "openai-completions",
      baseUrl: "https://api.platform.preferredai.jp/v1", reasoning: true, input: ["text"],
      contextWindow: 262144, maxTokens: 20480,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      thinkingLevelMap: { off: "none", minimal: null, low: null, medium: "medium", high: null, xhigh: null, max: null },
      compat: { supportsStore: false, supportsDeveloperRole: false, supportsReasoningEffort: true,
        supportsUsageInStreaming: true, supportsStrictMode: false, maxTokensField: "max_tokens" }
    })),
    api: { "openai-completions": { stream, streamSimple } }
  }));
}

export function plamoResolution(config, models) {
  const failure = reason => ({ supported: false, reason, provider: config.provider, model: config.model });
  if (config.model === "plamo-3.1-prime-deep-research") return failure("plamo_background_jobs_unsupported");
  const model = models.getModel("plamo", config.model);
  if (!model) return failure("pi_model_missing");
  const contract = config.catalogContract;
  if (contract?.npm && !["@ai-sdk/openai", "@ai-sdk/openai-compatible"].includes(contract.npm)) return failure("catalog_contract_ambiguous");
  if (contract?.shape && !["chat", "chat-completions", "chat_completions"].includes(contract.shape)) return failure("protocol_conflict");
  if (contract?.api && ![model.baseUrl, `${model.baseUrl}/chat/completions`].includes(contract.api.replace(/\/+$/, ""))) return failure("endpoint_conflict");
  if (contract && ((contract.reasoning != null && contract.reasoning !== model.reasoning) ||
      (contract.input != null && JSON.stringify(contract.input) !== JSON.stringify(model.input)) ||
      (contract.contextWindow != null && contract.contextWindow !== model.contextWindow) ||
      (contract.maxTokens != null && contract.maxTokens !== model.maxTokens) ||
      (contract.toolCall != null && contract.toolCall !== true))) return failure("catalog_contract_conflict");
  if (config.thinkingLevel && !["off", "medium"].includes(config.thinkingLevel)) return failure("plamo_reasoning_effort_unsupported");
  return { supported: true, provider: model.provider, model: model.id, api: model.api, source: "verified_official_contract",
    reasoning: true, supportedThinkingLevels: ["off", "medium"], input: model.input,
    contextWindow: model.contextWindow, maxTokens: model.maxTokens, toolCall: true };
}

export function plamoPayload(payload, request, config) {
  const nativeTools = (request.tools || []).filter(tool => tool.type !== "function");
  if (!nativeTools.length) return payload;
  if (nativeTools.some(tool => tool.type !== "plamo_web_search")) throw new Error("plamo_native_tool_unsupported");
  if (config.model !== "plamo-3.1-prime") throw new Error("plamo_web_search_unsupported");
  const value = { ...payload, web_search_options: {} };
  // PLaMo search rejects function tools and sampling settings, including defaults.
  for (const field of ["tools", "tool_choice", "temperature", "top_p", "presence_penalty", "frequency_penalty", "seed", "n", "stop", "logprobs"]) delete value[field];
  return value;
}
