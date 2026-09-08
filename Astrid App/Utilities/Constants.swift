import Foundation

@preconcurrency enum Constants {
    @preconcurrency enum API {
        // MARK: - Environment Configuration

        // Cached base URL to avoid repeated UserDefaults reads and logging
        // This is computed once at first access and cached
        private static let _cachedBaseURL: String = {
            #if DEBUG
            // A UI-test run carries a PRODUCTION session for uitest@astrid.cc, so it must talk
            // to production — a Debug build otherwise points at localhost:3000 and the request
            // fails, which is what left the whole suite signed out. See `resolvedBaseURL`.
            let resolved = UITestSession.resolvedBaseURL(
                isUITesting: UITestSession.isUITesting,
                debugPreference: Foundation.UserDefaults.standard.string(forKey: "debug_server_url"),
                defaultURL: environment.baseURL,
                productionURL: Environment.production.baseURL)
            AppLog.debug("🌐 [Constants.API.baseURL] Using: \(resolved)")
            return resolved
            #else
            return environment.baseURL
            #endif
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
                    // The simulator shares the Mac's loopback, so localhost just works.
                    #if targetEnvironment(simulator)
                    return "http://localhost:3000"
                    #else
                    // A physical device needs a routable address, and this used to be one
                    // developer's home LAN IP baked into tracked source (AITD-351). Anyone else —
                    // or the same person on another network — got an unreachable host with no
                    // hint why. Point at production unless this build was actually given a dev
                    // server, which is the same reasoning the macOS branch above already uses.
                    return API.devServerURL ?? Brand.productionBaseURL
                    #endif
                case .production:
                    return Brand.productionBaseURL
                }
            }
        }

        /// This build's own dev-server URL, if it was given one.
        ///
        /// Comes from the `AstridDevServerURL` Info.plist key, which `Info-Debug.plist` fills
        /// from the `ASTRID_DEV_SERVER_URL` build setting — typically defined in an untracked
        /// `Debug.xcconfig`. See `docs/XCODE_SETUP.md`.
        ///
        /// Nil when unset, which is the default and the point: no machine's address lives in the
        /// repository, so a Debug build on someone else's device falls back to production rather
        /// than silently pointing at a host that does not answer (AITD-351).
        static var devServerURL: String? {
            guard let value = Bundle.main.object(forInfoDictionaryKey: "AstridDevServerURL") as? String else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // An undefined build setting expands to the empty string rather than disappearing.
            guard !trimmed.isEmpty, trimmed != "$(ASTRID_DEV_SERVER_URL)" else { return nil }
            return trimmed
        }

        // Available server options for DEBUG builds
        #if DEBUG
        enum ServerOption: String, CaseIterable {
            case localhost = "localhost"
            /// The developer's own dev server. Offered only when this build has one — see
            /// `available`.
            case devServer = "dev-server"
            case production = "production"

            /// The URL this option selects. `production` resolves through Brand, so a
            /// rebranded build points at its own host.
            var url: String {
                switch self {
                case .localhost: return "http://localhost:3000"
                case .devServer: return API.devServerURL ?? Brand.productionBaseURL
                case .production: return Brand.productionBaseURL
                }
            }

            /// The options worth showing. The dev-server row is hidden unless one is configured,
            /// because an entry that silently means "production" is worse than no entry.
            static var available: [ServerOption] {
                allCases.filter { $0 != .devServer || API.devServerURL != nil }
            }

            var displayName: String {
                switch self {
                case .localhost: return "Localhost (Simulator)"
                case .devServer: return "Dev Server (Device)"
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
