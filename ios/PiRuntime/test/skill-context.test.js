import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { prepareSkillContext } from "../src/skill-context.js";

function fixture(t, name = "review-helper", extra = "") {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-skill-test-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const filePath = path.join(root, "SKILL.md");
  fs.writeFileSync(filePath, `---\nname: ${name}\ndescription: Review changes\n${extra}---\nFollow the review checklist.\n`);
  return { name, description: "stale native description", filePath, root };
}
function explicit(skill, messageIndex = 0) {
  return { catalog: [skill], explicitlyRequestedNames: [skill.name], skillFilePaths: [skill.filePath], explicitMessageIndices: [messageIndex] };
}

test("Pi loads metadata and expands explicit invocations through AgentSession", async t => {
  const skill = fixture(t);
  const request = { messages: [{ role: "user", content: "@review-helper check this" }], skillContext: explicit(skill) };
  const { request: applied, tools } = await prepareSkillContext(request);
  assert.equal(request.messages[0].content, "@review-helper check this");
  assert.equal(applied.messages[0].content, `<skill name="review-helper" location="${skill.filePath}">\nReferences are relative to ${skill.root}.\n\nFollow the review checklist.\n</skill>\n\n@review-helper check this`);
  assert.match(applied.systemPrompt, /<available_skills>/);
  assert.match(applied.systemPrompt, /<description>Review changes<\/description>/);
  assert.doesNotMatch(applied.systemPrompt, /stale native description/);
  assert.equal(tools[0].name, "read");
  const read = await tools[0].execute("read-skill", { path: skill.filePath });
  assert.match(read.content[0].text, /Follow the review checklist/);
});

test("rejects incomplete invocation context instead of silently skipping it", async () => {
  await assert.rejects(prepareSkillContext({ skillContext: { explicitlyRequestedNames: ["review-helper"] } }), /context is incomplete/);
});

test("keeps prior invocations and native attachments while combining skills in order", async t => {
  const first = fixture(t, "first");
  const second = fixture(t, "second");
  const attachments = [{ fileName: "image.png" }];
  const request = { messages: [
    { role: "user", content: "Review", attachments },
    { role: "assistant", content: "done" }, { role: "user", content: "continue" }
  ], skillContext: { catalog: [first, second], explicitlyRequestedNames: ["first", "second"], skillFilePaths: [first.filePath, second.filePath], explicitMessageIndices: [0, 0] } };
  const { request: applied } = await prepareSkillContext(request);
  assert.ok(applied.messages[0].content.indexOf('<skill name="first"') < applied.messages[0].content.indexOf('<skill name="second"'));
  assert.equal(applied.messages[0].attachments, attachments);
  assert.equal(applied.messages[2].content, "continue");
});

test("Pi honors disable-model-invocation while allowing explicit invocation", async t => {
  const skill = fixture(t, "manual", "disable-model-invocation: true\n");
  const { request } = await prepareSkillContext({ messages: [{ role: "user", content: "/skill:manual" }], skillContext: explicit(skill) });
  assert.doesNotMatch(request.systemPrompt, /<available_skills>/);
  assert.match(request.messages[0].content, /^<skill name="manual"/);
});

test("Pi read operations reject host files, installation state and symlink escapes", async t => {
  const skill = fixture(t);
  const outside = fixture(t, "outside");
  fs.writeFileSync(path.join(skill.root, "state.json"), "private");
  fs.symlinkSync(outside.filePath, path.join(skill.root, "escape.md"));
  const { tools } = await prepareSkillContext({ skillContext: { catalog: [skill] } });
  for (const filePath of [outside.filePath, path.join(skill.root, "state.json"), path.join(skill.root, "escape.md")]) {
    await assert.rejects(tools[0].execute("read-denied", { path: filePath }), /restricted|private/);
  }
});

test("missing enabled skills fail instead of falling back to stale native instructions", async t => {
  const skill = fixture(t);
  fs.unlinkSync(skill.filePath);
  await assert.rejects(prepareSkillContext({ skillContext: explicit(skill) }), /could not load/);
});

test("leaves requests untouched without enabled skills", async () => {
  const request = { messages: [{ role: "user", content: "Hello" }] };
  assert.equal((await prepareSkillContext(request)).request, request);
});
