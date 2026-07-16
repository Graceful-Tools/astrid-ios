import Foundation

/// TEMPORARY debug logger for diagnosing the Mac Google sign-in completion bug.
///
/// `NSLog` does not reliably surface from the sandboxed Mac app via `log show`, so this
/// appends to a file inside the app's sandbox container. Retrieve from the host with:
///
///   cat ~/Library/Containers/Graceful-Tools-Inc.Astrid-Mac/Data/tmp/gauth-debug.log
///
/// Remove this file and its callers once the Google sign-in bug is fixed.
enum GAuthDebug {
    private static let fileURL: URL =
        FileManager.default.temporaryDirectory.appendingPathComponent("gauth-debug.log")

    static func log(_ message: String) {
        NSLog("[GAUTH] %@", message)
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
