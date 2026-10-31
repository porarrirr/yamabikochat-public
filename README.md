# YamabikoChat

iPhone / iPad 向けの SwiftUI 製 AI チャットアプリです。複数モデルの比較、モデル同士の会話、Pi Agents によるツール実行、インタラクティブ UI に対応しています。プロバイダーの利用には、ご自身の API キーまたは対応アカウントが必要です。

## 公開内容

アプリ・共有拡張のソース、テスト、GenUI ソースと生成物、ビルド補助、依存ライブラリのライセンスを収録しています。個人メモ、開発レビュー記録、診断結果、App Store 提出資料、会話データ、認証情報、署名設定、非公開リポジトリの Git 履歴は収録しません。

Bundle ID と App Group は `org.example.yamabikochat` 系の開発用値です。実機配布では `ios/project.yml`、両ターゲットの entitlements、`AppConstants.swift`、Info.plist の識別子を自分のものに揃え、Xcode で自分の開発チームを指定してください。アプリ内のサポートと案内先はこの公開リポジトリに設定しています。再配布する場合は自分の案内先・プライバシーポリシー・利用条件に更新してください。

著作権表示と依存元の出典はライセンスのため保持しています。

## 開発環境とセットアップ

macOS、Xcode 27.1、XcodeGen、Node.js 24、Python 3 を使用します。Xcode 構成の正本は `ios/project.yml` です。

**現在の制約:** NodeMobile の検証済み配布マニフェスト `ios/node-mobile-release.json` は元ソースにも含まれていません。このためクリーン環境で `bootstrap.sh` はそのままでは完了しません。取得先やチェックサムを推測したファイルは同梱していません。

先に NodeMobile 配布元の検証済みリリースから次のフィールドを持つマニフェストを用意してください。`nodeVersion` は Node.js 24 のバージョン、`archiveURL` は `bootstrap-node-mobile.sh` が許可する配布元のリリースアーカイブ URL、`archiveSHA256` はその SHA-256 です。アーカイブには実機・シミュレーターの arm64 XCFramework と `third_party/nodejs-mobile/LICENSE` に一致するライセンスが必要です。第三者の別ランタイムへの自動置換は行いません。

```sh
cd ios
./bootstrap.sh
open YamabikoChat.xcodeproj
```

Python は WebKit Worker 内の Pyodide を使用します。bootstrap が固定済みの配布物を検証して取得します。詳しくは [Python の隔離設計](ios/docs/python-security.md) を参照してください。

GenUI の正本は `ios/GenUIAssets/` です。変更時は次のコマンドでアプリ内の生成物も更新します。

```sh
cd ios/GenUIAssets
npm install --ignore-scripts
python3 build.py
```

## 検証

```sh
python3 scripts/check-public-content.py
npm ci --prefix ios/PiRuntime
npm test --prefix ios/PiRuntime
npm ci --prefix ios/GenUIRuntimeTests --ignore-scripts
npm test --prefix ios/GenUIRuntimeTests
python3 -m unittest ios/PythonTests/test_yamabiko_runtime.py
npm run check:contracts --prefix ios/PiRuntime
```

上流契約の検証はネットワーク接続が必要です。iOS テストは bootstrap 完了後に実行します。

```sh
cd ios
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO test
```

## ライセンス

オリジナルコードは [MIT License](LICENSE) です。依存ソフトウェアの条件は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) と `third_party/` を参照してください。
