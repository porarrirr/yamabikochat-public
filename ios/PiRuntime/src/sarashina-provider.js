// Official contract: https://docs.sarashina.ai/api-reference/chat-completions
// Model limits: https://docs.sarashina.ai/models
// Drift check: scripts/check-sarashina-contract.py
import { createProvider, envApiKeyAuth } from "@earendil-works/pi-ai";
import { stream, streamSimple } from "@earendil-works/pi-ai/api/openai-completions";
export const sarashinaModels = [
  { id: "sarashina3.2-mini-thinking", contextWindow: 128000, toolCall: true, reasoning: true },
  { id: "sarashina3-mini", contextWindow: 128000, toolCall: true, reasoning: false },
  { id: "sarashina3-nano", contextWindow: 128000, toolCall: true, reasoning: false },
  { id: "sarashina3-guard", contextWindow: 64000, toolCall: false, reasoning: false }
];
export function installSarashinaProvider(models) {
  models.setProvider(createProvider({
    id: "sarashina", name: "Sarashina",
    auth: { apiKey: envApiKeyAuth("Sarashina API key", ["SARASHINA_API_KEY"]) },
    models: sarashinaModels.map(({ id, contextWindow, reasoning }) => ({
      id, name: id, provider: "sarashina", api: "openai-completions",
      baseUrl: "https://api.sarashina.ai/v1", reasoning, input: ["text"],
      contextWindow, maxTokens: 8000,
      ...(reasoning ? { thinkingLevelMap: { off: null, minimal: null, low: "low", medium: "medium", high: "high", xhigh: null, max: null } } : {}),
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      compat: { supportsStore: false, supportsDeveloperRole: false, supportsReasoningEffort: reasoning,
        supportsUsageInStreaming: false, supportsStrictMode: false, maxTokensField: "max_completion_tokens" }
    })),
    api: { "openai-completions": { stream, streamSimple } }
  }));
}
export function sarashinaResolution(config, models) {
  const model = models.getModel("sarashina", config.model);
  const failure = (reason) => ({ supported: false, reason, provider: config.provider, model: config.model });
  if (!model) return failure("pi_model_missing");
  const contract = config.catalogContract;
  if (contract?.npm && !["@ai-sdk/openai", "@ai-sdk/openai-compatible"].includes(contract.npm)) return failure("catalog_contract_ambiguous");
  if (contract?.shape && !["chat", "chat-completions", "chat_completions"].includes(contract.shape)) return failure("protocol_conflict");
  if (contract?.api && ![model.baseUrl, `${model.baseUrl}/chat/completions`].includes(contract.api.replace(/\/+$/, ""))) return failure("endpoint_conflict");
  if (contract && ((contract.reasoning != null && contract.reasoning !== model.reasoning) ||
      (contract.input != null && JSON.stringify(contract.input) !== JSON.stringify(model.input)) ||
      (contract.contextWindow != null && contract.contextWindow !== model.contextWindow) ||
      (contract.maxTokens != null && contract.maxTokens !== model.maxTokens))) return failure("catalog_contract_conflict");
  if (config.thinkingLevel && !(model.reasoning ? ["low", "medium", "high"] : ["off"]).includes(config.thinkingLevel)) return failure("sarashina_reasoning_unsupported");
  return { supported: true, provider: model.provider, model: model.id, api: model.api, source: "verified_official_contract",
    reasoning: model.reasoning, input: model.input, contextWindow: model.contextWindow, maxTokens: model.maxTokens,
    toolCall: sarashinaModels.find((entry) => entry.id === model.id).toolCall && (contract ? contract.toolCall === true : true) };
}

export function sarashinaResponseFailure(message) {
  if (message.provider !== "sarashina" || message.model !== "sarashina3.2-mini-thinking" || message.stopReason !== "length") return null;
  if (message.content.some(part => (part.type === "text" && part.text.trim()) || part.type === "toolCall")) return null;
  return Object.assign(new Error("Sarashina API reached its 8,000-token output limit, including thinking, before returning an answer. Lower Reasoning Effort to low or medium and retry."), {
    code: "sarashina_output_limit_before_answer"
  });
}
