# Local Python and credential isolation

## Trust boundaries

Pi remains the sole AI execution path. It calls the native `python_execute` tool
with code and a conversation workspace identity. Python does not receive provider
configuration, API keys, OAuth credentials, the Pi loopback token, or native paths.

Python 3.14 executes as the pinned Pyodide 314.0.7 WebAssembly distribution in a
module Worker inside an ephemeral WKWebView WebContent process. The app no longer
links the native CPython framework or calls a native CPython bridge. A Python audit
hook is useful for mistakes but is **not** a security boundary: code can change all
Python and worker-JavaScript globals without acquiring native app privileges.

The parent WebKit page enforces a `connect-src 'none'` CSP inherited by its Worker.
A compiled content rule blocks network and file-scheme resources. Navigation and
new-window creation are denied. No `loadFileURL` read-access grant, host filesystem
mount, network proxy, native execution bridge, or Keychain API is exposed. Browser
storage is nonpersistent. Escaping the Python namespace still leaves code inside
the WebKit/WebAssembly boundary.

## Offline runtime

`scripts/bootstrap-python-wasm.py` verifies the npm distribution SHA-512 and every
scientific package's SHA-256 from its authenticated upstream lock. It bundles only
NumPy, Matplotlib, Pillow and their locked dependencies. The app verifies the asset
manifest before loading them. Immutable bytes are passed into the worker's memory;
the Pyodide loader reads those bytes with an in-memory fetch implementation while
real network requests remain blocked by CSP. No CDN or package installation is
available at runtime. Noto fonts are copied into the virtual `/fonts` directory.

The pinned WASM core's declared maximum memory is reduced to 512 MiB during
bootstrap, with a fail-closed check on the original memory section. This limit is
enforced by the WASM engine, rather than a mutable Python/JavaScript watchdog.

## Workspace broker

The native broker copies the selected session workspace into a virtual
`/workspace`. It rejects absolute paths, traversal, NULs, backslashes, duplicate
paths, conflicting file/directory paths, symlinks, excessive depth, and oversized
files. Limits are 1024 files, 25 MiB per file, 100 MiB total and depth 16. The trusted
parent validates result shape and size before forwarding anything to Swift. Swift
validates it again, including artifact existence and size.

All returned files are staged before replacing the native workspace. A baseline
comparison rejects stale writes when an editor changed files during execution.
Rejected transfers leave the original native workspace intact. Python cannot ask
the broker to read another file or return data from the Keychain.

Successful cells in the same session retain variables. At most two recently used
session workers are retained, preventing an unbounded number of WebContent processes.
An evicted session starts with a fresh namespace and its last committed files.
Reset destroys the entire
worker. Timeout or cancellation terminates the worker and discards uncommitted
file changes; the next cell starts with a fresh namespace and last committed files.
The WebContent process can also be reclaimed by iOS; that is a recoverable tool
failure, never a reason to fall back to native execution.

## Installed skill files

Enabled, user-trusted skills are copied separately into virtual `/skills/<name>/`
for `python_execute`. The skill snapshot uses the same path, symlink and size
validation as workspace transfers; `state.json` is excluded. Each call refreshes
these copies, removing disabled or deleted skill files. Only `/workspace` is
returned and committed: worker changes can never replace native installed skills.
The Python audit policy permits reading skill copies and rejects ordinary writes;
as above, the audit policy itself is not a security boundary.

The root agent still runs through Pi. Native code owns installation, trust,
enablement and the UI's `@name` / legacy `$name` aliases. Pi's public `loadSkills`
parses installed files, `formatSkillsForPrompt` advertises them (including
`disable-model-invocation`), and `AgentSession.steer` expands `/skill:name` through
its public queue API without running inference. The previous hand-written skill
block formatter and `activate_skill` / `read_skill_resource` tools are removed.
Pi's `createReadTool` owns file reading and truncation with restricted operations
that allow only the enabled skill directories, exclude installation state, and
resolve symlinks before access. PCC dispatches this Pi-owned tool through the
same authenticated runtime callback used for Pi subagents.

Python uses `/skills/<name>/` copies, while Pi's read tool uses installation
locations. The runtime explains the mapping. Compatible Python scripts run with
`runpy` and explicit arguments. Shell commands, subprocesses, network access and
dependencies outside the bundled runtime remain unavailable; this integration
does not provide full desktop Pi skill compatibility.

`BundledAgentSkills/skill-creator` is seeded enabled on first availability, with
a persistent record so later launches preserve user replacements, disabling and
deletion. Generated skills are returned as importable files; the model cannot
silently install new instructions.

## Credential lifecycle and transport

Credentials use device-only Keychain items with background-compatible accessibility;
existing items are upgraded on read. Pi's standard SDK transport rejects redirects.
External providers require HTTPS; HTTP is allowed only for exact loopback hosts.
No alternate endpoint, model, protocol, or provider is tried after rejection.

Each runtime request owns a credential redactor. It removes known credential values
from free-text errors as well as structured secret fields before diagnostics leave
Pi. iOS sanitizes persisted/exported snapshots again; a database migration removes
old diagnostic error bodies whose unknown secret values cannot be reconstructed.

OAuth logout cancels matching native streams, aborts matching root/child runs,
clears Pi's in-memory credentials, and invalidates pending login/refresh generations.
A signed-out provider cannot restore an old token set through a late resolve call.
ChatGPT additionally follows its documented renewable-session revocation flow.

## Verification

Regression tests cover the original audit-hook bypass with a synthetic host file,
native Security-framework loading, browser network APIs, invalid file transfers,
parallel editor conflicts, scientific PNG generation, state/reset/timeout behavior,
credential-bearing redirects, all five custom wire protocols, diagnostic redaction,
Keychain item migration and logout races. No real user credentials are used in tests.

The boundary assumes current iOS/WebKit/WebAssembly security. This is not a promise
against OS/browser vulnerabilities or that the model-generated program is correct.
