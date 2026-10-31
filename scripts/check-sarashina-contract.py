#!/usr/bin/env python3
"""Fail on changes to the official Sarashina fields used by Pi; never infer new routes."""
import json
import re
import subprocess
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = False
    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script"): self.skip = True
    def handle_endtag(self, tag):
        if tag in ("style", "script"): self.skip = False
    def handle_data(self, data):
        if not self.skip: self.parts.append(data)

def page(path):
    request = urllib.request.Request("https://docs.sarashina.ai/" + path, headers={"User-Agent": "YamabikoChat-contract-check"})
    with urllib.request.urlopen(request, timeout=20) as response:
        parser = Text()
        parser.feed(response.read().decode())
        return "".join(parser.parts)

chat, models = page("api-reference/chat-completions"), page("models")
assert "https://api.sarashina.ai/v1/chat/completions" in chat, "Sarashina endpoint drift"
assert re.search(r"max_completion_tokens.*?1から8000", chat, re.S), "Sarashina output limit drift"
assert re.search(r"stream_options.*?サポートしていません", chat, re.S), "Sarashina stream_options support drift"
assert '"system", "user", "assistant", "tool"' in chat, "Sarashina message role drift"
assert re.search(r"content.*?string / null", chat, re.S), "Sarashina message content type drift"
assert "delta.reasoning" in chat and "base64" in chat, "Sarashina encrypted reasoning drift"
assert re.search(r"reasoning_effort.*?low.*?medium.*?high", chat, re.S), "Sarashina thinking levels drift"
for model in ("sarashina3.2-mini-thinking", "sarashina3-mini", "sarashina3-nano", "sarashina3-guard"):
    assert model in chat, f"Sarashina model removed: {model}"
assert re.search(r"Sarashina3.2 mini thinking.*?128k", models, re.S)
assert re.search(r"Sarashina3 mini.*?128k", models, re.S)
assert re.search(r"Sarashina3 nano.*?128k", models, re.S)
assert re.search(r"Sarashina3 guard.*?64k", models, re.S)
root = Path(__file__).resolve().parents[1]
runtime = json.loads(subprocess.check_output([
    "node", "--input-type=module", "-e",
    'import { createModels, getSupportedThinkingLevels } from "@earendil-works/pi-ai"; '
    'import { installSarashinaProvider } from "./src/sarashina-provider.js"; '
    'const models = createModels(); installSarashinaProvider(models); '
    'console.log(JSON.stringify(models.getModels("sarashina").map(model => ({ '
    '...model, levels: getSupportedThinkingLevels(model) }))));'
], cwd=root / "ios/PiRuntime", text=True))
expected = {"sarashina3.2-mini-thinking", "sarashina3-mini", "sarashina3-nano", "sarashina3-guard"}
assert {model["id"] for model in runtime} == expected, "Sarashina runtime model drift"
native = (root / "ios/YamabikoChat/Shared/ProviderDisplay.swift").read_text()
for model in runtime:
    assert model["id"] in native, f"Sarashina native mapping missing: {model['id']}"
    assert model["baseUrl"] == "https://api.sarashina.ai/v1" and model["api"] == "openai-completions"
    assert model["maxTokens"] == 8000
    assert model["contextWindow"] == (64000 if model["id"] == "sarashina3-guard" else 128000)
    thinking = model["id"] == "sarashina3.2-mini-thinking"
    assert model["reasoning"] == thinking
    assert model["compat"]["supportsReasoningEffort"] == thinking
    assert model["levels"] == (["low", "medium", "high"] if thinking else ["off"])
print("Sarashina official contract matches Pi and native mappings")
