import SwiftUI
import UIKit

@main
struct YamabikoChatApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .background(KeyboardDismissalHost())
                .scrollDismissesKeyboard(.never)
        }
    }
}

private struct AppBootstrapView: View {
    @State private var services: AppServices?
    @State private var initializationError: Error?
    @State private var isRetrying = false

    var body: some View {
        Group {
            if let services {
                AppRootHost(services: services)
            } else if let initializationError {
                DatabaseRecoveryView(
                    error: initializationError,
                    isRetrying: isRetrying,
                    onRetry: initialize
                )
            } else {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            }
        }
        .task {
            if services == nil, initializationError == nil {
                await initializeAsync()
            }
        }
    }

    private func initialize() {
        Task { await initializeAsync() }
    }

    private func initializeAsync() async {
        guard !isRetrying else { return }
        isRetrying = true
        initializationError = nil
        do {
            async let resolvedServices = AppServices.resolve()
            // Every app web view requires the WebKit network block before it is created.
            try await YamabikoWebKitSupport.prepareNetworkPolicy()
            services = try await resolvedServices
        } catch {
            initializationError = error
            DiagnosticsLogger.log("App initialization failed", category: .app, error: error)
        }
        isRetrying = false
    }
}

private struct AppRootHost: View {
    @StateObject private var container: AppContainer
    @StateObject private var appState = AppState()
    @StateObject private var onboarding: OnboardingViewModel

    init(services: AppServices) {
        _container = StateObject(wrappedValue: AppContainer(services: services))
        _onboarding = StateObject(wrappedValue: OnboardingViewModel(store: services.onboardingStore))
    }

    var body: some View {
        Group {
            if onboarding.isCompleted || AppStoreScreenshotRouting.isEnabled {
                RootView()
            } else {
                OnboardingScreen(viewModel: onboarding, settings: onboarding.settings)
            }
        }
            .environmentObject(container)
            .environmentObject(appState)
            .onOpenURL { url in
                if let id = SiriConversationService.conversationID(from: url) {
                    do {
                        _ = try SiriConversationService.resolve(id: id, repository: container.conversationRepository)
                        SiriNavigation.shared.request(.conversation(id))
                    } catch {
                        DiagnosticsLogger.log("Siri conversation link unavailable", category: .app, error: error)
                    }
                    return
                }
                guard url == AppConstants.importShareURL else { return }
                while appState.importSharePayload(
                    from: container.sharePayloadStore,
                    repository: container.chatRepository
                ) {}
            }
    }
}

private struct DatabaseRecoveryView: View {
    let error: Error
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.text("データベースを開けません"), systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(error.localizedDescription)
                .textSelection(.enabled)
        } actions: {
            Button(L10n.text("再試行"), action: onRetry)
                .disabled(isRetrying)
            Button(L10n.text("エラーをコピー")) {
                UIPasteboard.general.string = error.localizedDescription
            }
        }
        .padding()
    }
}
