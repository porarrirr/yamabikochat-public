#!/usr/bin/env python3
"""Verify PLaMo's official contract and the native/Pi model mapping."""
import json
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DocumentText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def load_url(url):
    return subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "30", url],
        capture_output=True, text=True, check=True,
    ).stdout


def main():
    parser = DocumentText()
    parser.feed(load_url("https://docs.plamo.preferredai.jp/ja/api"))
    text = " ".join(parser.parts)
    table = text[text.index("モデル ID"):text.index("サンプル", text.index("モデル ID"))]
    models = re.findall(r"(plamo-[\w.-]+)\s+([\d,]+) トークン\s+([\d,]+) トークン\s+対応", table)
    assert models, "PLaMo model table missing"
    expected = [{"id": model, "contextWindow": int(context.replace(",", "")),
                 "maxTokens": int(output.replace(",", ""))} for model, context, output in models]
    assert "POST  https://api.platform.preferredai.jp/v1/chat/completions" in text, "PLaMo endpoint drift"
    assert re.search(r"reasoning_effort.*?none.*?medium.*?のみ", text, re.S), "PLaMo reasoning contract drift"
    assert re.search(r"対応モデルは\s+plamo-3.1-prime\s+です", text), "PLaMo search model drift"
    assert re.search(r"次のパラメータは指定できません.*?temperature.*?tools.*?tool_choice", text, re.S), "PLaMo search exclusions drift"
    assert re.search(r"background: true.*?非同期ジョブのみ", text, re.S), "PLaMo Responses lifecycle drift"
    assert "plamo-3.1-prime-deep-research" in text, "PLaMo Deep Research ID drift"
    catalog = json.loads(load_url("https://models.dev/catalog.json"))["providers"]
    upstream = [(provider_id, provider) for provider_id, provider in catalog.items()
                if "preferredai.jp" in json.dumps(provider) or "plamo" in provider_id.lower()]
    configs = []
    for provider_id, provider in upstream:
        assert provider_id == "plamo", f"New PLaMo catalog identity requires explicit mapping: {provider_id}"
        for model_id, model in provider["models"].items():
            route = model.get("provider", {})
            configs.append({"provider": "plamo", "model": model_id, "catalogContract": {
                "npm": route.get("npm", provider["npm"]), "api": route.get("api", provider.get("api")),
                "shape": route.get("shape"), "reasoning": model.get("reasoning"),
                "input": model["modalities"]["input"], "toolCall": model.get("tool_call"),
                "contextWindow": model["limit"]["context"], "maxTokens": model["limit"]["output"]}})
    script = """
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createModels, getSupportedThinkingLevels } from '@earendil-works/pi-ai';
import { installPlamoProvider, plamoModels, plamoResolution } from './src/plamo-provider.js';
const { expected, configs } = JSON.parse(fs.readFileSync(0, 'utf8'));
const models = createModels(); installPlamoProvider(models);
assert.deepEqual(plamoModels, expected.map(m => m.id));
for (const entry of expected) {
  const m = models.getModel('plamo', entry.id);
  assert.equal(m.baseUrl, 'https://api.platform.preferredai.jp/v1');
  assert.equal(m.contextWindow, entry.contextWindow);
  assert.equal(m.maxTokens, entry.maxTokens);
  assert.deepEqual(getSupportedThinkingLevels(m), ['off', 'medium']);
}
for (const config of configs) {
  const result = plamoResolution(config, models);
  assert.ok(result.supported || result.reason === 'plamo_background_jobs_unsupported', JSON.stringify(result));
}
"""
    subprocess.run(["node", "--input-type=module", "-e", script], input=json.dumps({"expected": expected, "configs": configs}),
                   text=True, cwd=ROOT / "ios/PiRuntime", check=True)
    native = (ROOT / "ios/YamabikoChat/Shared/ProviderDisplay.swift").read_text()
    match = re.search(r'case "PLAMO": \[([^\]]+)\]', native)
    assert match and re.findall(r'"([^"]+)"', match[1]) == [model["id"] for model in expected], "Native PLaMo model mapping drift"
    print(f"PLaMo official contract matches Pi and native mappings ({len(expected)} chat models)")


if __name__ == "__main__":
    main()
