import test from "node:test";
import assert from "node:assert/strict";
import { contextBreakdown } from "../src/context-breakdown.js";

test("estimates system prompt, tool definitions, and messages separately with Pi's estimator", () => {
  const tool = { name: "lookup", description: "Find a record", parameters: { type: "object", properties: {} } };
  const breakdown = contextBreakdown({
    systemPrompt: "s".repeat(40),
    tools: [tool],
    messages: [
      { role: "system", content: "", toolsAdded: [tool] },
      { role: "user", content: "u".repeat(8) },
      { role: "assistant", content: [{ type: "text", text: "a".repeat(12) }] }
    ]
  });
  assert.equal(breakdown.contextSystemPromptTokens, 10);
  assert.equal(breakdown.contextToolDefinitionTokens,
    Math.ceil(JSON.stringify([{ name: tool.name, description: tool.description, parameters: tool.parameters }]).length / 4));
  assert.equal(breakdown.contextMessageTokens, 5);
});

test("reports zero for an absent system prompt or tool set", () => {
  assert.deepEqual(contextBreakdown({ systemPrompt: "", tools: [], messages: [] }), {
    contextSystemPromptTokens: 0, contextToolDefinitionTokens: 0, contextMessageTokens: 0
  });
});
