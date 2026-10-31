import { credentialFetch } from "./credential-security.js";

// main.js imports this module first, so dependencies that capture fetch while their
// modules evaluate also receive the policy. Applies to Pi's SDKs as well as OAuth;
// the Google SDK uses the global transport rather than Pi's per-request fetch hook.
globalThis.fetch = credentialFetch(globalThis.fetch.bind(globalThis));
