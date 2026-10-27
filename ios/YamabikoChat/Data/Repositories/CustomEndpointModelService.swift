import Foundation

struct CustomEndpointDiscoveredModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// Catalog discovery only; all inference continues through Pi's provider APIs.
struct CustomEndpointModelService {
    var httpClient: HTTPClientProtocol = URLSessionHTTPClient()

    func fetch(baseURL: String, apiProtocol: String, apiKey: String?) async throws -> [CustomEndpointDiscoveredModel] {
        guard let base = URL(string: baseURL), SecureProviderEndpoint.isAllowed(base),
              base.query == nil, base.fragment == nil else {
            throw DiscoveryError.invalidURL
        }
        var headers = ["Accept": "application/json"]
        switch apiProtocol {
        case "openai-completions", "openai-responses", "mistral-conversations":
            if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        case "anthropic-messages":
            headers["anthropic-version"] = "2023-06-01"
            if let apiKey, !apiKey.isEmpty { headers["x-api-key"] = apiKey }
        case "google-generative-ai":
            if let apiKey, !apiKey.isEmpty { headers["x-goog-api-key"] = apiKey }
        default:
            throw DiscoveryError.protocolRequired
        }
        let url = base.appendingPathComponent("models")
        var results: [CustomEndpointDiscoveredModel] = []
        var seenIDs = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?
        // Pagination stays on the explicitly configured endpoint, including auth.
        for _ in 0..<100 {
            try Task.checkCancellation()
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            if let cursor {
                components.queryItems = [URLQueryItem(
                    name: apiProtocol == "anthropic-messages" ? "after_id" : "pageToken", value: cursor
                )]
            }
            let (data, response) = try await httpClient.send(HTTPRequest(
                url: components.url!, method: "GET", headers: headers, timeoutInterval: 30
            ))
            guard (200...299).contains(response.statusCode) else {
                // Do not expose server response bodies: proxies can echo credentials.
                throw DiscoveryError.httpStatus(response.statusCode)
            }
            let page = try Self.parse(data, apiProtocol: apiProtocol)
            for model in page.models where seenIDs.insert(model.id).inserted { results.append(model) }
            guard let next = page.nextCursor else {
                return results.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            }
            guard seenCursors.insert(next).inserted else { throw DiscoveryError.invalidPagination }
            cursor = next
        }
        throw DiscoveryError.invalidPagination
    }

    static func parse(_ data: Data, apiProtocol: String) throws -> (models: [CustomEndpointDiscoveredModel], nextCursor: String?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root[apiProtocol == "google-generative-ai" ? "models" : "data"] as? [[String: Any]] else {
            throw DiscoveryError.invalidCatalog
        }
        let models = try entries.map { entry -> CustomEndpointDiscoveredModel in
            let rawID = entry[apiProtocol == "google-generative-ai" ? "name" : "id"] as? String
            guard var id = rawID, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DiscoveryError.invalidCatalog
            }
            // Gemini resource names use models/{id}; Pi expects the unqualified ID.
            if apiProtocol == "google-generative-ai", id.hasPrefix("models/") { id.removeFirst("models/".count) }
            guard !id.isEmpty else { throw DiscoveryError.invalidCatalog }
            return CustomEndpointDiscoveredModel(id: id, name: (entry["display_name"] as? String) ?? (entry["displayName"] as? String) ?? (entry["name"] as? String) ?? id)
        }
        var cursor: String?
        if apiProtocol == "anthropic-messages", root["has_more"] as? Bool == true {
            guard let lastID = root["last_id"] as? String, !lastID.isEmpty else { throw DiscoveryError.invalidPagination }
            cursor = lastID
        } else if apiProtocol == "google-generative-ai" {
            cursor = (root["nextPageToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return (models, cursor)
    }

    enum DiscoveryError: LocalizedError {
        case invalidURL, protocolRequired, invalidCatalog, invalidPagination, httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "有効なBase URLを入力してください。"
            case .protocolRequired: return "APIプロトコルを選択してください。"
            case .invalidCatalog: return "モデル一覧の形式を読み取れません。モデルIDを手入力できます。"
            case .invalidPagination: return "モデル一覧のページを取得できませんでした。"
            case .httpStatus(let status): return "モデル一覧を取得できませんでした（HTTP \(status)）。認証と/modelsへの対応を確認してください。モデルIDを手入力できます。"
            }
        }
    }
}
