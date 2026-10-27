import { mobileAgentDir } from "./subagent-environment.js";
import fs from "node:fs/promises";
import path from "node:path";
import { Agent } from "@earendil-works/pi-agent-core";
import { AgentSession, DefaultResourceLoader, SessionManager, SettingsManager, createReadTool, formatSkillsForPrompt, loadSkills } from "@earendil-works/pi-coding-agent";

// iOS owns installation and enablement. Pi owns parsing, discovery metadata,
// prompt formatting, command expansion, and the read tool implementation.
export async function prepareSkillContext(request, modelRuntime) {
  const context = request?.skillContext;
  if (!context) return { request, tools: [] };
  const names = context.explicitlyRequestedNames || [];
  const filePaths = context.skillFilePaths || [];
  const indices = context.explicitMessageIndices || [];
  if (filePaths.length !== names.length || indices.length !== names.length) {
    throw new Error("Pi skill invocation context is incomplete");
  }
  const catalog = context.catalog || [];
  const skillPaths = [...new Set([...catalog.map(skill => skill.filePath), ...filePaths])];
  if (skillPaths.some(value => typeof value !== "string" || !path.isAbsolute(value))) {
    throw new Error("Pi skill context requires installed absolute file paths");
  }
  if (!skillPaths.length) return { request, tools: [] };
  const loaded = loadSkills({ cwd: mobileAgentDir, agentDir: mobileAgentDir, skillPaths, includeDefaults: false });
  for (const filePath of skillPaths) {
    if (!loaded.skills.some(skill => path.resolve(skill.filePath) === path.resolve(filePath))) {
      throw new Error(`Pi could not load installed skill: ${filePath}`);
    }
  }
  const skills = loaded.skills;
  const roots = await Promise.all(skills.map(skill => fs.realpath(skill.baseDir)));
  const authorize = async filePath => {
    const actual = await fs.realpath(filePath);
    if (!roots.some(root => actual.startsWith(root + path.sep))) throw new Error("read is restricted to enabled skill files; use str_replace_editor for workspace files");
    if (path.basename(actual) === "state.json") throw new Error("Skill installation state is private");
    return actual;
  };
  const read = createReadTool(mobileAgentDir, {
    autoResizeImages: false,
    operations: {
      access: async filePath => { await fs.access(await authorize(filePath)); },
      readFile: async filePath => fs.readFile(await authorize(filePath)),
      detectImageMimeType: async () => null
    }
  });
  const messages = [...(request.messages || [])];
  if (names.length) {
    const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
    const resourceLoader = new DefaultResourceLoader({
      cwd: mobileAgentDir, agentDir: mobileAgentDir, settingsManager,
      noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
      skillsOverride: () => loaded
    });
    await resourceLoader.reload();
    // Queue expansion is a public AgentSession API. No inference is performed:
    // take the expanded text from Pi's queue and let the existing root Agent run.
    const session = new AgentSession({
      agent: new Agent(), modelRuntime, resourceLoader, settingsManager,
      cwd: mobileAgentDir, sessionManager: SessionManager.inMemory(mobileAgentDir),
      baseToolsOverride: {}, initialActiveToolNames: []
    });
    try {
      const promptsByMessage = new Map();
      for (let index = 0; index < names.length; index++) {
        const messageIndex = indices[index];
        if (!Number.isInteger(messageIndex) || messages[messageIndex]?.role !== "user") throw new Error("Pi skill invocation references an invalid user message");
        const skill = skills.find(skill => skill.name === names[index] && path.resolve(skill.filePath) === path.resolve(filePaths[index]));
        if (!skill) throw new Error(`Pi skill invocation is unavailable: ${names[index]}`);
        await session.steer(`/skill:${skill.name}`);
        const expanded = session.getSteeringMessages().at(-1);
        session.clearQueue();
        if (!expanded || expanded === `/skill:${skill.name}`) throw new Error(`Pi skill expansion failed: ${skill.name}`);
        promptsByMessage.set(messageIndex, [...(promptsByMessage.get(messageIndex) || []), expanded]);
      }
      for (const [messageIndex, prompts] of promptsByMessage) {
        messages[messageIndex] = { ...messages[messageIndex], content: [...prompts, messages[messageIndex].content || ""].join("\n\n") };
      }
    } finally { session.dispose(); }
  }
  const visible = skills.filter(skill => catalog.some(entry => entry.filePath === skill.filePath));
  const catalogPrompt = formatSkillsForPrompt(visible, "read");
  const runtime = "iOS skill runtime: Pi skill locations are readable with read. In python_execute, the same enabled skill files are copied to /skills/<skill-name>/, not the native location shown by read. Run compatible Python scripts with runpy.run_path and sys.argv; add the script directory to sys.path for sibling imports and restore both afterwards. Write inputs/outputs under /workspace. Shell, subprocess, network, and unbundled dependencies are unavailable. Report required steps that fail or cannot run; do not claim unperformed checks succeeded.";
  return {
    request: { ...request, messages, systemPrompt: [request.systemPrompt, catalogPrompt, runtime].filter(Boolean).join("\n\n") },
    tools: [read]
  };
}
