# Credential and conversation boundaries

Inference and authentication remain on the Pi provider path. These controls do not
make a cloud provider an offline service or change its retention rules.

- A secret single or dual conversation carries `executionPolicy` with both client
  tools and subagents disabled. The gateway omits child configurations and credentials.
  Pi enforces the policy before skills, extensions, provider discovery for children,
  or tool execution. Legacy requests with `supportsClientTools=false` are restricted too.
- Authentication failures expose fixed messages and allowlisted codes, never response
  bodies, JSON parser excerpts, upstream free text, or exception causes. Native decoding
  also replaces malformed authentication responses with a fixed error.
- Credential-bearing native sessions and Pi transports reject redirects. Browser
  authorization URLs must use the exact approved HTTPS authentication hosts.
- ChatGPT and SuperGrok stop active runs and attempt session revocation on logout.
  Refresh and revoke operations share a provider-scoped queue so revocation uses the
  latest rotated tokens. SuperGrok revokes both refresh and access tokens at the endpoint
  advertised by `https://auth.x.ai/.well-known/openid-configuration` (RFC 7009).
  A missing or untrusted endpoint and an unsuccessful response fail closed. Local
  credentials are deleted even when remote revocation is unconfirmed, and the UI
  explicitly reports that the user should review provider account connections.
- The pinned pi-grok provider uses an ephemeral loopback port and checks state and
  request method before consuming successful or error callbacks. No replacement login,
  refresh, protocol, provider, or model fallback is introduced.
- Keychain secrets use `WhenUnlockedThisDeviceOnly`, with synchronization disabled.
  Startup upgrades dormant credentials too. Locked-device background credential reads
  can therefore fail and must wait until the device is unlocked.
- Internal attachments, generated files, queued share drafts, and temporary exports use
  iOS Complete File Protection and backup exclusion. This is OS-managed file encryption,
  not an application-defined ciphertext format. New generated files live in private
  Application Support; prior Documents files keep their existing references and receive
  the same protection. Implicit Documents file sharing is disabled. Explicit user export
  and share actions still create readable copies for the chosen destination.
- The app and share extension declare `default-data-protection = NSFileProtectionComplete`,
  so every new file in their containers is Complete Protection by OS default. The explicit
  per-file attributes remain for files created before the entitlement. The App IDs and
  provisioning profiles must enable Data Protection with Complete Protection.
- Every app web view is created by `YamabikoWebKitSupport.makeConfiguration`, which uses a
  non-persistent data store and attaches a compiled WebKit rule list blocking all http(s),
  ws(s) and ftp loads, independent of page HTML or CSP. The app shows no UI until the rule
  list is compiled. The only exception is the isolated YouTube player, which receives a
  validated 11-character video ID. The Python sandbox keeps its own stricter rule list.
- GenUI documents never widen the canvas policy (`img-src data:`, `connect-src 'none'`).
  Every network contact a document can cause (links, image lightbox, share URLs, remote
  images) passes a native confirmation alert naming the destination hosts; generated code
  can forge taps inside the canvas but not that alert. Consented remote images are fetched
  natively with an ephemeral session, checked as decodable images, and returned as data URLs.
  Remote audio, video and Lottie files are not loaded in the canvas.
- Siri, Shortcuts and Spotlight receive only `ExternalConversationSummary` (id, title, date)
  from `ConversationRepository.externalConversationSummaries`, which excludes secret
  conversations in SQL and searches titles only. Message-body search is foreground in-app only.
- `src/transport-policy.js` is the first import of `main.js`, so the redirect and HTTPS
  policy wraps `globalThis.fetch` before any dependency module evaluates.
- Export completion/dismissal removes its ZIP. Startup removes abandoned ZIP/staging
  copies and attachment staging files. A migration removes historical app diagnostic
  files in both Debug and Release. Copies already shared outside the app and OS logs
  from previous builds cannot be recalled by this change.

`npm test` includes offline regression tests for restricted requests, wrong-state and
non-GET callbacks, malformed token bodies, revocation failures, and refresh/revoke races.
It also exercises all Pi built-in identities and protocol kinds. The xAI metadata drift
check is `python3 scripts/check-supergrok-auth-contract.py` from the repository root.
The provider patch is applied and checked on dependency installation and every build.
Real account credentials are not needed by these tests.

Before distribution, verify the signed Release on physical devices for lock/unlock,
backup/restore, external-browser sign-in and provider-side revocation. Simulator tests
cannot certify those device and service behaviors or prove that a past leak never
occurred.
