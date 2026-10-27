import { estimateTokens } from "@earendil-works/pi-coding-agent";
import { toToolDeclaration } from "@earendil-works/pi-ai/utils/transcript";

// Per-category context occupancy estimated with Pi's chars/4 estimator. The
// provider reports only the total, so these values are estimates by contract.
export function contextBreakdown({ systemPrompt, tools, messages }) {
  return {
    contextSystemPromptTokens: estimateTokens({ role: "system", content: systemPrompt || "" }),
    contextToolDefinitionTokens: (tools || []).length
      ? estimateTokens({ role: "system", content: "", toolsAdded: tools.map(toToolDeclaration) })
      : 0,
    // Transcript system messages carry tool declarations already counted above.
    contextMessageTokens: (messages || [])
      .filter((message) => message.role !== "system")
      .reduce((sum, message) => sum + estimateTokens(message), 0)
  };
}
