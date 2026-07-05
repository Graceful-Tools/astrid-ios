import Foundation

/// Classifies an error thrown by a handler into an `OutboxResult`, so transient
/// failures back off and retry while terminal ones dead-letter. Pure.
enum OutboxResultMapper {
    static func classify(_ error: Error) -> OutboxResult {
        if let apiError = error as? AstridAPIError {
            switch apiError {
            case .unauthorized:
                return .permanent("unauthorized")
            case .invalidURL:
                return .permanent("invalid URL")
            case .httpError(let statusCode, let message):
                return OutboxScheduler.isPermanentFailure(httpStatus: statusCode)
                    ? .permanent("HTTP \(statusCode): \(message)")
                    : .retryable("HTTP \(statusCode): \(message)")
            case .invalidResponse, .decodingError:
                // Could be a flaky/partial response — worth a retry.
                return .retryable(apiError.localizedDescription)
            }
        }
        // Connectivity failures must NOT burn attempts — 8 retries × backoff is
        // only ~4 minutes, so a short offline stretch would permanently
        // dead-letter queued writes in an offline-first app. Treat these as
        // .blocked (waits without consuming attempts) until the network
        // returns. Other URLErrors (and unknown errors) stay retryable.
        if isOfflineURLError(error) {
            return .blocked("offline: \((error as NSError).localizedDescription)")
        }
        return .retryable(error.localizedDescription)
    }

    /// True for URLError codes that mean "no usable network right now".
    static func isOfflineURLError(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .dataNotAllowed, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}
