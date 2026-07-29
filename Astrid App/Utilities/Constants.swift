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

        // Default environment (can be overridden in DEBUG with the debug_server_url preference).
        #if DEBUG
        #if os(macOS)
        // The Mac app has no local dev-server workflow (it isn't a simulator and defaults to a
        // LAN IP that isn't reachable), so hit production by default even in Debug. A local URL
        // can still be set via the debug_server_url preference / Connection settings.
        static let environment: Environment = .production
        #else
        static let environment: Environment = .development
        #endif
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
                    return Brand.productionBaseURL
                }
            }
        }

        // Available server options for DEBUG builds
        #if DEBUG
        enum ServerOption: String, CaseIterable {
            case localhost = "http://localhost:3000"
            case localNetwork = "http://192.168.50.254:3000"
            case production = "production"

            /// The URL this option selects. `production` resolves through Brand, so a
            /// rebranded build points at its own host; the others are developer-local.
            var url: String {
                switch self {
                case .localhost, .localNetwork: return rawValue
                case .production: return Brand.productionBaseURL
                }
            }

            var displayName: String {
                switch self {
                case .localhost: return "Localhost (Simulator)"
                case .localNetwork: return "Local Network (Device)"
                case .production: return "Production (\(Brand.host))"
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
    
    // `enum UI` lived here: hex copies of the theme palette, commented "Match web app
    // colors", with nothing to keep them matching. Removed in the whitelabel refactor
    // (task 97208a72) — a second colour source can only drift from the first, and this
    // one had already drifted all the way into dead code with no readers at all.
    //
    // Colours have exactly two homes now: Theme.swift for surfaces, Brand.swift for the
    // brand accent. scripts/check-brand.sh keeps it that way.

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
