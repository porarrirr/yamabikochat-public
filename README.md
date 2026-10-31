<div align="center">

<img src="assets/readme/icon.png" alt="YamabikoChat app icon" width="112">

# YamabikoChat

**Chat with AI, compare answers, and get things done on iPhone and iPad.**

A native SwiftUI AI chat client. Use multiple models in one app with your own API keys or supported accounts.

**English** · [日本語](README.ja.md)

<a href="https://apps.apple.com/jp/app/yamabikochat-ai%E3%83%81%E3%83%A3%E3%83%83%E3%83%88/id6771687018"><img src="assets/readme/app-store-badge-en.svg" alt="Download on the App Store" width="180"></a>

[Get the iPhone and iPad app](https://apps.apple.com/jp/app/yamabikochat-ai%E3%83%81%E3%83%A3%E3%83%83%E3%83%88/id6771687018) · [Build from source](#development-and-setup) · [MIT License](LICENSE)

</div>

## Features

| Feature | What you can do |
| --- | --- |
| Chat | Stream responses, edit messages, regenerate answers, and switch between response variants. |
| Dual mode | Send the same prompt to two models and compare their answers side by side. |
| Auto conversation | Choose models, a topic, and a turn count to run a conversation between models. |
| Tools and subagents | Search the web, run Python, edit files, ask follow-up questions, and delegate work. |
| Rich responses | Display Markdown, tables, code, math, Mermaid, SVG, and interactive GenUI components. |
| Organization | Manage projects, search history, save model presets, and inspect token usage. |
| iOS integration | Use Siri, Shortcuts, Spotlight, the Share Extension, and image and file attachments. |
| iPad and languages | Split layouts, dark mode, and English, Japanese, Simplified Chinese, Spanish, and French. |

## Get started

1. [Install YamabikoChat from the App Store](https://apps.apple.com/jp/app/yamabikochat-ai%E3%83%81%E3%83%A3%E3%83%83%E3%83%88/id6771687018).
2. Select a provider in Settings, then enter your API key or sign in with a supported account.
3. Choose a model and start a conversation. Enable dual mode, auto conversation, or tools as needed.

Connections include Google Gemini, OpenRouter, ChatGPT plan, xAI, Apple Intelligence, Sarashina, PLaMo, and custom endpoints. The models.dev catalog provides additional provider and model listings. Availability depends on your provider plan, authentication method, device and OS, and Pi runtime support. Provider charges follow each service's terms.

The App Store app does not require Xcode or a source checkout. This repository contains source for development and testing; its update schedule may differ from the App Store release.

## Data and execution

Conversations and settings are stored on your device. API keys and authentication tokens are managed in the iOS Keychain. AI requests are sent to your selected provider. When search or remote tools are enabled, information needed for those operations is also sent to their endpoints.

AI execution, provider authentication, usage, and context management use the embedded **Pi Agents** runtime. Unsupported models display a reason instead of being automatically replaced by another model or protocol. Python runs through Pyodide in a WebKit Worker.

- [Privacy policy](ios/PRIVACY.md) and [terms of use](ios/TERMS.md)
- [Credential and conversation boundaries](ios/PiRuntime/SECURITY.md)
- [Python isolation design](ios/docs/python-security.md)

## Repository layout

| Path | Contents |
| --- | --- |
| `ios/YamabikoChat/` | SwiftUI app, data management, and native tools. |
| `ios/YamabikoShareExtension/` | Share Extension for text and URLs from other apps. |
| `ios/PiRuntime/` | Pi Agents runtime, provider integrations, and JavaScript tests. |
| `ios/GenUIAssets/` | Source of truth for GenUI widgets, tokens, and icons. |
| `ios/YamabikoTests/` and `ios/YamabikoUITests/` | Swift unit and UI tests. |
| `ios/GenUIRuntimeTests/` and `ios/PythonTests/` | DOM and Python runtime tests. |
| `ios/scripts/` and `scripts/` | Build helpers, upstream contract checks, and public content checks. |
| `third_party/` | Dependency licenses. |

The public source includes the app, Share Extension, runtimes, generated UI assets, tests, and build helpers. It excludes personal notes, development review records, App Store submission materials, conversation data, credentials, and signing configuration. Copyright notices and dependency attribution are preserved.

## Build and redistribute with your own settings

Bundle IDs and App Groups use development placeholders under `org.example.yamabikochat`. For device distribution, update identifiers consistently in `ios/project.yml`, both targets' entitlements, `AppConstants.swift`, and Info.plist, then select your own development team in Xcode.

In-app support and information links point to this public repository. Before redistributing, replace them with your own support destinations, privacy policy, and terms of use.

## Development and setup

Use macOS, Xcode 27.1, XcodeGen, Node.js 24, and Python 3. The Xcode configuration source of truth is `ios/project.yml`.

**Current limitation:** The verified NodeMobile distribution manifest, `ios/node-mobile-release.json`, is missing from the original source as well. A clean checkout cannot complete `bootstrap.sh` without it. No guessed download URL or checksum is included.

First obtain a manifest for a verified NodeMobile release. It must contain `nodeVersion` (a Node.js 24 version), `archiveURL` (a release archive URL accepted by `bootstrap-node-mobile.sh`), and `archiveSHA256` (its SHA-256). The archive must include arm64 XCFramework slices for devices and simulators, plus a license matching `third_party/nodejs-mobile/LICENSE`. Bootstrap does not automatically substitute a different runtime.

```sh
cd ios
./bootstrap.sh
open YamabikoChat.xcodeproj
```

Python uses Pyodide in a WebKit Worker. Bootstrap downloads and verifies the pinned distribution. See the [Python isolation design](ios/docs/python-security.md).

GenUI sources live in `ios/GenUIAssets/`. After changes, regenerate the assets included in the app:

```sh
cd ios/GenUIAssets
npm install --ignore-scripts
python3 build.py
```

## Validation

```sh
python3 scripts/check-public-content.py
npm ci --prefix ios/PiRuntime
npm test --prefix ios/PiRuntime
npm ci --prefix ios/GenUIRuntimeTests --ignore-scripts
npm test --prefix ios/GenUIRuntimeTests
python3 -m unittest ios/PythonTests/test_yamabiko_runtime.py
npm run check:contracts --prefix ios/PiRuntime
```

Upstream contract checks require network access. Run iOS tests after bootstrap completes:

```sh
cd ios
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO test
```

## License

Original code is available under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `third_party/` for dependency licenses.
