import Foundation

protocol APIClientProtocol {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
}

class APIClient: APIClientProtocol {
    static let shared = APIClient()

    /// Dynamic baseURL that reads current server preference
    private var baseURL: URL {
        URL(string: Constants.API.baseURL)!
    }
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.API.timeout
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // Try ISO8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }
        
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }
    
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        var request = try endpoint.makeRequest(baseURL: baseURL, encoder: encoder)

        // Add session cookie if available
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            PrivacyLogger.debug("APIClient", "authentication=missing")
        }

        PrivacyLogger.request("APIClient", method: endpoint.method.rawValue, url: request.url)

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        PrivacyLogger.response("APIClient", status: httpResponse.statusCode, bytes: data.count)
        
        // Save session cookies - collect ALL auth-related cookies
        // Note: allHeaderFields is [AnyHashable: Any], convert to [String: String] manually
        if let url = httpResponse.url {
            var stringHeaders: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    stringHeaders[keyString] = valueString
                }
            }

            let cookies = HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: url)
            var authCookies: [String] = []
            for cookie in cookies {
                let lowercaseName = cookie.name.lowercased()
                if lowercaseName.contains("session") || lowercaseName.contains("auth") || lowercaseName.contains("csrf") {
                    authCookies.append("\(cookie.name)=\(cookie.value)")
                }
            }

            if !authCookies.isEmpty {
                let allCookiesString = authCookies.joined(separator: "; ")
                do {
                    try KeychainService.shared.saveSessionCookie(allCookiesString)
                } catch {
                    print("❌ [APIClient] Keychain save failed: \(error)")
                }
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            PrivacyLogger.error("APIClient", code: "http_error", status: httpResponse.statusCode)

            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorResponse.error)
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
        
        // Handle empty responses
        if data.isEmpty {
            if let emptyResponse = EmptyResponse() as? T {
                return emptyResponse
            }
        }
        
        do {
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            PrivacyLogger.error("APIClient", code: "decoding_error", status: httpResponse.statusCode)
            throw APIError.decodingError(error)
        }
    }

    // MARK: - User Search

    /// Search for users with AI agents included (based on user's configured API keys)
    func searchUsersWithAIAgents(query: String, taskId: String?, listIds: [String]?) async throws -> [User] {
        let response: UserSearchResponse = try await request(.searchUsersWithAIAgents(
            query: query,
            taskId: taskId,
            listIds: listIds
        ))
        return response.users
    }
}

// MARK: - User Search Response

struct UserSearchResponse: Codable {
    let users: [User]
    let listMemberCount: Int?
}

// MARK: - Empty Response

struct EmptyResponse: Codable {}

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let message):
            if let message = message {
                return "HTTP \(code): \(message)"
            }
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized. Please sign in again."
        }
    }
}
