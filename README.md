# YamabikoChat

iPhone / iPad 向けの SwiftUI 製 AI チャットアプリです。複数モデルの比較、モデル同士の会話、Pi Agents によるツール実行に対応しています。

## 構成

- `ios/YamabikoChat/` — アプリ本体
- `ios/YamabikoShareExtension/` — 共有拡張
- `ios/PiRuntime/` — アプリ内の AI 実行ランタイム
- `ios/GenUIAssets/` — インタラクティブ UI のソース
- `ios/YamabikoTests/`・`ios/YamabikoUITests/`・`ios/GenUIRuntimeTests/`・`ios/PythonTests/` — テスト
- `ios/scripts/`・`scripts/` — ビルド補助とプロバイダー契約の検証
- `third_party/` — 依存ライブラリのライセンス

## 開発環境

macOS、Xcode 27.1、XcodeGen、Node.js 24、Python 3 を使用します。構成の正本は `ios/project.yml` です。実機向けの署名には、自分の Apple Developer チームと Bundle ID を設定してください。

```sh
cd ios
./bootstrap.sh
open YamabikoChat.xcodeproj
```

NodeMobile と Python の実行環境は bootstrap で取得します。NodeMobile には、`ios/scripts/bootstrap-node-mobile.sh` が検証するリリース URL・Node.js バージョン・SHA-256 を定義した `ios/node-mobile-release.json` が必要です。このスナップショットの元ソースにはそのファイルが含まれていないため、クリーン環境での bootstrap はそのままでは完了しません。

## 検証

```sh
npm ci --prefix ios/PiRuntime
npm test --prefix ios/PiRuntime
npm ci --prefix ios/GenUIRuntimeTests --ignore-scripts
npm test --prefix ios/GenUIRuntimeTests
python3 -m unittest ios/PythonTests/test_yamabiko_runtime.py
```

## ライセンス

オリジナルコードは [MIT License](LICENSE) で公開しています。依存ソフトウェアのライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) と `third_party/` を参照してください。
