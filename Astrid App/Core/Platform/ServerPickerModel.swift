import Combine
import Foundation

/// "Use a different server" on the sign-in screen (ADEV-118), for iOS and Mac alike.
///
/// Turns what was typed into an origin, asks that server whether it is one to use, then hands
/// it to `ServerSwitcher`. Every failure is a sentence a person can act on.
@MainActor
final class ServerPickerModel: ObservableObject {
    @Published var address = ""
    @Published private(set) var isChecking = false
    @Published private(set) var errorMessage: String?

    private let probe: (String) async throws -> ServerCapabilities
    private let switchTo: (String?) async -> Void

    init(probe: @escaping (String) async throws -> ServerCapabilities = { try await ServerProbe.live.check($0) },
         switchTo: @escaping (String?) async -> Void = { await ServerSwitcher.shared.use($0) }) {
        self.probe = probe
        self.switchTo = switchTo
    }

    var canConnect: Bool { !isChecking && !address.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Check and switch. True when the app now talks to the new server.
    func connect() async -> Bool {
        errorMessage = nil
        let origin: String
        switch ServerSelection.origin(from: address) {
        case .success(let value):
            origin = value
        case .failure(let error):
            errorMessage = Self.message(for: error)
            return false
        }

        isChecking = true
        defer { isChecking = false }
        let host = URL(string: origin)?.host ?? origin
        do {
            let capabilities = try await probe(origin)
            // Too old for this app: say so now, not after a sign-in that never returns (ADEV-121).
            guard !ServerCompatibility.isTooOld(capabilities) else {
                errorMessage = ServerCompatibility.message(host: host)
                return false
            }
        } catch {
            errorMessage = Self.message(for: error as? ServerProbe.Failure ?? .unreachable, host: host)
            return false
        }
        await switchTo(origin)
        return true
    }

    /// Back to the build's own server.
    func useBrandServer() async {
        await switchTo(nil)
    }

    static func message(for error: ServerSelection.InputError) -> String {
        switch error {
        case .notHTTPS: return NSLocalizedString("server.error_not_https", comment: "")
        case .empty, .invalid: return NSLocalizedString("server.error_invalid", comment: "")
        }
    }

    static func message(for failure: ServerProbe.Failure, host: String) -> String {
        switch failure {
        case .unreachable:
            return String(format: NSLocalizedString("server.error_unreachable", comment: ""), host)
        case .notAstrid:
            return String(format: NSLocalizedString("server.error_not_astrid", comment: ""), host)
        }
    }
}
