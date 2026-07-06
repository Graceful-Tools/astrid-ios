import Foundation

extension Error {
    /// The HTTP status carried by an API error, if any. Sync workers use this
    /// to branch on "already gone" (404/410) after a remote delete/close
    /// without string-matching `"\(error)"`, which breaks the moment an error
    /// description changes or a localized build renders a different message.
    var syncHTTPStatusCode: Int? {
        if let apiError = self as? AstridAPIError,
           case let .httpError(statusCode, _) = apiError { return statusCode }
        if let apiError = self as? APIError,
           case let .httpError(statusCode, _) = apiError { return statusCode }
        return nil
    }

    /// The remote twin is already gone — safe to clear a pending deletion.
    var syncRemoteAlreadyGone: Bool {
        syncHTTPStatusCode == 404 || syncHTTPStatusCode == 410
    }
}
