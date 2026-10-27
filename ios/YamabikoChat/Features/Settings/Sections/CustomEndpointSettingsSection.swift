import SwiftUI

struct CustomEndpointSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section("カスタムエンドポイント") {
            if !viewModel.openAICompatPresets.isEmpty {
                Picker("プリセット", selection: Binding(
                    get: { viewModel.settings.selectedOpenAICompatPreset ?? "" },
                    set: { viewModel.selectCustomEndpointPreset($0) }
                )) {
                    Text("新規").tag("")
                    ForEach(viewModel.openAICompatPresets) { Text($0.name).tag($0.name) }
                }
            }
            TextField("プリセット名", text: $viewModel.customEndpointDraft.name)
            Picker("APIプロトコル", selection: $viewModel.customEndpointDraft.apiProtocol) {
                Text("選択してください").tag("")
                Text("Anthropic Messages").tag("anthropic-messages")
                Text("OpenAI Chat Completions").tag("openai-completions")
                Text("OpenAI Responses").tag("openai-responses")
                Text("Gemini (Google Generative AI)").tag("google-generative-ai")
                Text("Mistral Native").tag("mistral-conversations")
            }
            .onChange(of: viewModel.customEndpointDraft.apiProtocol) { _, api in
                viewModel.invalidateCustomEndpointDiscovery()
                if api != "anthropic-messages" { viewModel.customEndpointDraft.thinkingBudget = nil }
            }
            TextField("Base URL", text: $viewModel.customEndpointDraft.baseURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .onChange(of: viewModel.customEndpointDraft.baseURL) { _, _ in viewModel.invalidateCustomEndpointDiscovery() }
            SecureField("APIキー（一覧取得にも使用）", text: $viewModel.openAICompatApiKeyInput)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: viewModel.openAICompatApiKeyInput) { _, _ in viewModel.invalidateCustomEndpointDiscovery() }
            Button {
                Task { await viewModel.fetchCustomEndpointModels() }
            } label: {
                HStack {
                    Text("サーバーからモデル一覧を取得")
                    if viewModel.customEndpointModelsLoading { ProgressView() }
                }
            }
            .disabled(viewModel.customEndpointModelsLoading || viewModel.customEndpointDraft.baseURL.isEmpty || viewModel.customEndpointDraft.apiProtocol.isEmpty)
            if let error = viewModel.customEndpointModelsError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if !viewModel.customEndpointDiscoveredModels.isEmpty {
                TextField("取得したモデルを検索", text: $viewModel.customEndpointModelSearch)
                    .textInputAutocapitalization(.never)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.filteredCustomEndpointDiscoveredModels) { model in
                            Button {
                                viewModel.chooseDiscoveredCustomEndpointModel(model.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(model.id)
                                    if model.name != model.id { Text(model.name).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
            if !viewModel.customEndpointDraft.models.isEmpty {
                Picker("登録済みモデルを編集", selection: Binding(
                    get: { viewModel.customEndpointDraft.models.contains(where: { $0.modelId == viewModel.customEndpointDraft.modelId }) ? viewModel.customEndpointDraft.modelId : "" },
                    set: { if $0.isEmpty { viewModel.newCustomEndpointModel() } else { viewModel.editCustomEndpointModel($0) } }
                )) {
                    Text("新しいモデル").tag("")
                    ForEach(viewModel.customEndpointDraft.models) { Text($0.modelId).tag($0.modelId) }
                }
            }
            Button("モデルを追加") { viewModel.newCustomEndpointModel() }
            Text("一覧から選択するかモデルIDを入力し、モデルごとの設定を確認して保存してください。上限・対応機能・APIプロトコルは自動判定しません。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("モデルID", text: $viewModel.customEndpointDraft.modelId)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            LabeledContent("コンテキスト上限") {
                TextField("tokens", value: $viewModel.customEndpointDraft.contextWindow, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("最大出力") {
                TextField("tokens", value: $viewModel.customEndpointDraft.maxTokens, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            Toggle("画像入力に対応", isOn: $viewModel.customEndpointDraft.vision)
            Toggle("ツール呼び出しに対応", isOn: $viewModel.customEndpointDraft.toolCall)
            Toggle("Reasoningに対応", isOn: $viewModel.customEndpointDraft.reasoning)
                .onChange(of: viewModel.customEndpointDraft.reasoning) { _, enabled in
                    if !enabled {
                        viewModel.customEndpointDraft.reasoningEffort = "off"
                        viewModel.customEndpointDraft.thinkingBudget = nil
                    }
                }
            if viewModel.customEndpointDraft.reasoning {
                Picker("Reasoning effort", selection: $viewModel.customEndpointDraft.reasoningEffort) {
                    ForEach(["off", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.customEndpointDraft.reasoningEffort) { _, effort in
                    if effort == "off" { viewModel.customEndpointDraft.thinkingBudget = nil }
                }
                if viewModel.customEndpointDraft.apiProtocol == "anthropic-messages" {
                    LabeledContent("Thinking budget") {
                        TextField("省略可", value: $viewModel.customEndpointDraft.thinkingBudget, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
            }
            LabeledContent("Temperature") {
                TextField("省略可・0〜2", value: $viewModel.customEndpointDraft.temperature, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            if viewModel.customEndpointDraft.apiProtocol == "openai-completions" {
                Picker("出力上限のパラメーター", selection: $viewModel.customEndpointDraft.maxTokensField) {
                    Text("max_completion_tokens").tag("max_completion_tokens")
                    Text("max_tokens").tag("max_tokens")
                }
                Toggle("storeパラメーターに対応", isOn: $viewModel.customEndpointDraft.supportsStore)
                Toggle("ストリーム内のusageに対応", isOn: $viewModel.customEndpointDraft.supportsUsageInStreaming)
            }
            if ["openai-completions", "openai-responses"].contains(viewModel.customEndpointDraft.apiProtocol) {
                Toggle("developerロールに対応", isOn: $viewModel.customEndpointDraft.supportsDeveloperRole)
            }
            Button("モデルとエンドポイントを保存") { viewModel.addOrUpdateOpenAICompatPreset() }
                .buttonStyle(.bordered)
            if let name = viewModel.settings.selectedOpenAICompatPreset, !name.isEmpty {
                Button("APIキーを保存") { viewModel.saveSelectedOpenAICompatApiKey() }
                if viewModel.customEndpointDraft.models.count > 1,
                   viewModel.customEndpointDraft.models.contains(where: { $0.modelId == viewModel.customEndpointDraft.modelId }) {
                    Button("編集中のモデルを削除", role: .destructive) {
                        viewModel.removeCustomEndpointModel(viewModel.customEndpointDraft.modelId)
                    }
                }
                Button("選択中のプリセットを削除", role: .destructive) { viewModel.removeOpenAICompatPreset(name: name) }
            }
        }
        .onAppear {
            if viewModel.customEndpointDraft.name.isEmpty, let selected = viewModel.settings.selectedOpenAICompatPreset {
                viewModel.selectCustomEndpointPreset(selected)
            }
        }
    }

}
