import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.org.example.yamabikochat"
    static let sharePayloadDidChangeNotification = Notification.Name("YamabikoSharePayloadDidChange")
    static let sharePayloadDarwinNotification = "org.example.yamabikochat.share_payload.changed"
    static let importShareURL = URL(string: "yamabikochat://import-share")!
    static let alibabaMCPAuthorizationTokenKey = "alibaba_mcp_authorization_token"
    static let alibabaMCPDefaultServerName = "firecrawl"
    static let firecrawlRemoteMCPURLTemplate = "https://mcp.firecrawl.dev/fc-YOUR_API_KEY/v2/mcp"

    static let maxAttachmentSizeBytes: Int = 10 * 1024 * 1024

    static let defaultOpenCodeGoBaseURL = URL(string: "https://opencode.ai/zen/go/v1/")!
    static let defaultClinePassBaseURL = URL(string: "https://api.cline.bot/api/v1/")!
    static let defaultAlibabaCodingPlanBaseURL = URL(string: "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/")!
    static let defaultZAICodingPlanBaseURL = URL(string: "https://api.z.ai/api/coding/paas/v4/")!
    static let defaultSuperGrokBaseURL = URL(string: "https://cli-chat-proxy.grok.com/v1/")!

    /// Public app information hosted in the shared Pages repository.
    static let marketingURL = URL(string: "https://github.com/porarrirr/yamabikochat-public")!
    static let privacyPolicyURL = URL(string: "https://github.com/porarrirr/yamabikochat-public/blob/main/ios/PRIVACY.md")!
    static let supportURL = URL(string: "https://github.com/porarrirr/yamabikochat-public/issues")!
    static let termsOfUseURL = URL(string: "https://github.com/porarrirr/yamabikochat-public/blob/main/ios/TERMS.md")!
}
