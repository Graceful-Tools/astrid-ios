import Foundation

/// Metadata-only diagnostics for security-sensitive code paths.
/// Messages are compiled out of Release builds and callers must never pass
/// tokens, headers, payloads, complete URLs, or account identifiers.
nonisolated enum PrivacyLogger {
    nonisolated static func debug(_ category: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        print("[\(category)] \(message())")
        #endif
    }

    nonisolated static func request(_ category: String, method: String, url: URL?) {
        #if DEBUG
        let path = url?.path(percentEncoded: false) ?? "<invalid-path>"
        print("[\(category)] request method=\(method) path=\(path)")
        #endif
    }

    nonisolated static func response(_ category: String, status: Int, bytes: Int) {
        #if DEBUG
        print("[\(category)] response status=\(status) bytes=\(bytes)")
        #endif
    }

    nonisolated static func error(_ category: String, code: String, status: Int? = nil) {
        #if DEBUG
        if let status {
            print("[\(category)] error code=\(code) status=\(status)")
        } else {
            print("[\(category)] error code=\(code)")
        }
        #endif
    }
}
