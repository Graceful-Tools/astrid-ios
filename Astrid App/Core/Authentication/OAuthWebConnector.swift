import Foundation
import AuthenticationServices

/// Presents a provider OAuth URL in an in-app ASWebAuthenticationSession that auto-dismisses
/// when the flow redirects to `callbackScheme://…` — the same mechanism Google *sign-in* uses,
/// so connecting an integration (e.g. Google Tasks) returns to the app instead of stranding the
/// user on a web page. The backend callback finishes by navigating to the app scheme.
@MainActor
final class OAuthWebConnector: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthWebConnector()

    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    enum ConnectError: LocalizedError {
        case missingCallback
        case presentationFailed
        var errorDescription: String? {
            switch self {
            case .missingCallback: return "The connection didn't return a result."
            case .presentationFailed: return "Couldn't present the connection window. Please try again."
            }
        }
    }

    /// Present `url` and resolve with the callback URL once the flow redirects to `callbackScheme`.
    /// Throws on user-cancel or presentation failure.
    func present(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                if let error { self?.finish(.failure(error)); return }
                guard let callback else { self?.finish(.failure(ConnectError.missingCallback)); return }
                self?.finish(.success(callback))
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false   // reuse the Google login cookie
            self.session = session
            if !session.start() { self.finish(.failure(ConnectError.presentationFailed)) }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.session = nil
        continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PlatformApplication.presentationAnchor()
    }
}
