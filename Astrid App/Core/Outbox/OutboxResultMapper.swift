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
        // URLError and anything else: treat as transient and retry.
        return .retryable(error.localizedDescription)
    }
}
