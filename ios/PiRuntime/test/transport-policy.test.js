import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

test("the global transport policy is installed before any other runtime module evaluates", async () => {
  const main = fs.readFileSync(new URL("../src/main.js", import.meta.url), "utf8");
  assert.equal(main.split("\n")[0], 'import "./transport-policy.js";');
  const original = globalThis.fetch;
  await import("../src/transport-policy.js");
  assert.notEqual(globalThis.fetch, original);
  await assert.rejects(globalThis.fetch("http://provider.example/v1"), { code: "insecure_provider_endpoint" });
});
