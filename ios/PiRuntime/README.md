# Pi runtime

AI execution, provider authentication, token usage, and context management use the
bundled Pi Agents runtime. `src/main.js` exposes an authenticated loopback bridge
to the native app. Provider resolution fails with a typed reason when the exact
model contract is unsupported; it does not retry through a different protocol.

Dependencies are pinned in `package-lock.json`. `npm ci` applies the maintained
Pi compatibility patches; `npm test` builds the bundle and runs the runtime tests.
`npm run check:contracts` compares provider contracts with upstream sources.
See [SECURITY.md](SECURITY.md) for credential and conversation boundaries.
