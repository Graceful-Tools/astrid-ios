import Foundation

@preconcurrency enum Constants {
    @preconcurrency enum API {
        // MARK: - Environment Configuration

        // Cached base URL to avoid repeated UserDefaults reads and logging
        // This is computed once at first access and cached
        private static let _cachedBaseURL: String = {
            #if DEBUG
            // In debug builds, check for user preference
            if let customURL = Foundation.UserDefaults.standard.string(forKey: "debug_server_url"), !customURL.isEmpty {
                print("🌐 [Constants.API.baseURL] Using server preference: \(customURL)")
                return customURL
            }
            print("🌐 [Constants.API.baseURL] Using default: \(environment.baseURL)")
            #endif
            return environment.baseURL
        }()

        // Get base URL - now returns cached value (no logging on every access)
        static var baseURL: String {
            return _cachedBaseURL
        }

        // Default environment (can be overridden in DEBUG with user preference)
        #if DEBUG
        static let environment: Environment = .development
        #else
        static let environment: Environment = .production
        #endif

        enum Environment {
            case development
            case production

            var baseURL: String {
                switch self {
                case .development:
                    // Use your local machine's IP address for testing on real device
                    // Simulator can use "localhost", real device needs IP address
                    #if targetEnvironment(simulator)
                    return "http://localhost:3000"
                    #else
                    return "http://192.168.50.254:3000"
                    #endif
                case .production:
                    return "https://astrid.cc"
                }
            }
        }

        // Available server options for DEBUG builds
        #if DEBUG
        enum ServerOption: String, CaseIterable {
            case localhost = "http://localhost:3000"
            case localNetwork = "http://192.168.50.254:3000"
            case production = "https://astrid.cc"

            var displayName: String {
                switch self {
                case .localhost: return "Localhost (Simulator)"
                case .localNetwork: return "Local Network (Device)"
                case .production: return "Production (astrid.cc)"
                }
            }
        }
        #endif

        static let timeout: TimeInterval = 30

        // SSE endpoint for real-time updates
        static let sseEndpoint = "/api/v1/sse"
    }
    
    enum Keychain {
        static let service = "com.astrid.ios"
        static let sessionCookieKey = "session_cookie"
        static let mcpTokenKey = "mcp_token"
    }
    
    enum UserDefaults {
        static let userId = "user_id"
        static let userEmail = "user_email"
        static let userName = "user_name"
        static let userImage = "user_image"
    }
    
    enum UI {
        // Match web app colors
        static let primaryColor = "3b82f6" // blue-500
        static let successColor = "10b981" // green-500
        static let warningColor = "f59e0b" // amber-500
        static let dangerColor = "ef4444" // red-500

        // Priority colors matching web app
        enum Priority {
            static let none = "gray"
            static let low = "10b981" // green
            static let medium = "f59e0b" // amber
            static let high = "ef4444" // red
        }
    }

    enum Lists {
        // Special list IDs
        static let bugsAndRequestsListId = "6afe098f-e163-46f7-ac4b-4f879a9314eb"
    }

    enum Localization {
        // Supported language codes (ISO 639-1)
        static let supportedLanguages = ["en", "es", "fr", "de", "it", "ja", "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"]

        // UserDefaults key for manual language override
        static let userLanguageOverrideKey = "user_language_override"

        // Spanish-speaking regions (ISO 3166-1 alpha-2 country codes)
        static let spanishSpeakingRegions: Set<String> = [
            "ES", // Spain
            "MX", // Mexico
            "AR", // Argentina
            "CO", // Colombia
            "CL", // Chile
            "PE", // Peru
            "VE", // Venezuela
            "EC", // Ecuador
            "GT", // Guatemala
            "CU", // Cuba
            "BO", // Bolivia
            "DO", // Dominican Republic
            "HN", // Honduras
            "PY", // Paraguay
            "SV", // El Salvador
            "NI", // Nicaragua
            "CR", // Costa Rica
            "PA", // Panama
            "UY", // Uruguay
            "PR", // Puerto Rico
            "GQ"  // Equatorial Guinea
        ]

        // French-speaking regions (ISO 3166-1 alpha-2 country codes)
        static let frenchSpeakingRegions: Set<String> = [
            "FR", // France
            "BE", // Belgium
            "CH", // Switzerland
            "CA", // Canada (Quebec)
            "LU", // Luxembourg
            "MC", // Monaco
            "CI", // Côte d'Ivoire
            "CM", // Cameroon
            "SN", // Senegal
            "ML", // Mali
            "BF", // Burkina Faso
            "NE", // Niger
            "CD", // Democratic Republic of Congo
            "CG", // Republic of Congo
            "MG", // Madagascar
            "BJ", // Benin
            "TG", // Togo
            "GN", // Guinea
            "RW", // Rwanda
            "BI", // Burundi
            "TD", // Chad
            "HT", // Haiti
            "GA", // Gabon
            "CF"  // Central African Republic
        ]
    }
}
