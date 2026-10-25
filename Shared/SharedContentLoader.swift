import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// What the share sheet handed over, ready for quick-create to prefill. The Share Extension's
/// logic lives here, in `Shared/`, so the app's unit tests can reach it — the appex itself is never
/// loaded by a test host (AITD-542).
struct SharedTaskDraft: Equatable {
    var title: String
    var notes: String
    var file: SharedFileData?

    /// The queued share for what the person confirmed, or nil while the title is blank — the
    /// same rule that disables Save.
    static func taskData(title: String, notes: String, priority: Int, file: SharedFileData?) -> SharedTaskData? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedTaskData(
            title: title,
            description: notes.isEmpty ? nil : notes,
            listId: nil, // The app files it in the default list
            priority: priority == 0 ? nil : priority,
            fileURL: file?.fileURL,
            fileName: file?.fileName,
            mimeType: file?.mimeType,
            fileSize: file?.fileSize
        )
    }

    /// A shared web page: its title, with the address in the notes.
    static func webPage(_ url: URL, pageTitle: String?) -> SharedTaskDraft {
        let pageTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title: String
        if !pageTitle.isEmpty && pageTitle != url.absoluteString {
            title = pageTitle
        } else if let host = url.host, !host.isEmpty {
            title = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else {
            title = url.absoluteString
        }
        return SharedTaskDraft(title: title, notes: url.absoluteString, file: nil)
    }

    /// Shared text: the first line is the title, the rest the notes. Text that is nothing but a
    /// web address is a web page — several apps share a link that way.
    static func text(_ text: String) -> SharedTaskDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil, !trimmed.contains(where: \.isWhitespace) {
            return webPage(url, pageTitle: nil)
        }
        var lines = trimmed.components(separatedBy: .newlines)
        let first = lines.isEmpty ? "" : lines.removeFirst()
        let notes = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedTaskDraft(title: first.trimmingCharacters(in: .whitespaces), notes: notes, file: nil)
    }

    /// A shared file or image: a pending attachment, titled from its name.
    static func file(_ file: SharedFileData) -> SharedTaskDraft {
        SharedTaskDraft(title: file.suggestedTitle, notes: "", file: file)
    }
}

extension SharedFileData {
    /// `vacation_photo-2.jpg` → `vacation photo 2`.
    var suggestedTitle: String {
        (fileName as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    /// The SF Symbol quick-create shows beside the attachment.
    var iconName: String {
        switch mimeType {
        case let type where type.hasPrefix("image/"): return "photo"
        case let type where type.hasPrefix("video/"): return "video"
        case let type where type.contains("pdf"): return "doc.fill"
        case let type where type.contains("text"): return "doc.text"
        case let type where type.contains("zip"), let type where type.contains("archive"): return "archivebox"
        default: return "doc"
        }
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: fileSize)
    }

    static func mimeType(forExtension fileExtension: String) -> String {
        UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// Turns the extension's input items into a draft: picks which representation to load, copies any
/// file into the App Group, and maps the rest to a title and notes.
struct SharedContentLoader {
    /// The representations the extension takes, most specific first. Order matters: a file URL
    /// is also a URL, and plain text and URLs are also data.
    enum Kind: CaseIterable {
        case image, fileURL, webURL, text, file

        var type: UTType {
            switch self {
            case .image: return .image
            case .fileURL: return .fileURL
            case .webURL: return .url
            case .text: return .plainText
            case .file: return .data
            }
        }

        static func of(_ provider: NSItemProvider) -> Kind? {
            allCases.first { provider.hasItemConformingToTypeIdentifier($0.type.identifier) }
        }
    }

    /// What a provider's item became, in a form that can cross the callback.
    private enum Loaded: Sendable {
        case url(URL), data(Data), text(String), nothing
    }

    let manager: ShareDataManager
    var now: () -> Date = Date.init

    /// The draft for the first attachment, or nil when there is none the extension can use.
    func draft(from items: [NSExtensionItem]) async throws -> SharedTaskDraft? {
        guard let item = items.first, let provider = item.attachments?.first,
              let kind = Kind.of(provider) else { return nil }
        let loaded = try await load(kind, from: provider)

        switch (kind, loaded) {
        case (.webURL, .url(let url)):
            let pageTitle = (item.attributedTitle ?? item.attributedContentText)?.string
            return .webPage(url, pageTitle: pageTitle)
        case (.text, .text(let text)):
            return .text(text)
        case (.text, .data(let data)):
            return String(data: data, encoding: .utf8).map(SharedTaskDraft.text)
        case (_, .url(let url)) where url.isFileURL:
            return .file(try copyFile(at: url))
        case (.image, .data(let data)):
            return .file(try copyData(data, named: "image_\(Int(now().timeIntervalSince1970)).jpg"))
        case (.file, .data(let data)):
            return .file(try copyData(data, named: "file"))
        default:
            return nil
        }
    }

    private func load(_ kind: Kind, from provider: NSItemProvider) async throws -> Loaded {
        switch kind {
        // `loadItem` hands a URL back as its archived property list, not a URL; the object
        // loaders decode it.
        case .fileURL, .webURL:
            return try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url { continuation.resume(returning: .url(url)) }
                    else if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: .nothing) }
                }
            }
        case .text, .image, .file:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: kind.type.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                switch item {
                case let url as URL: continuation.resume(returning: .url(url))
                case let data as Data: continuation.resume(returning: .data(data))
                case let text as String: continuation.resume(returning: .text(text))
                #if canImport(UIKit)
                case let image as UIImage:
                    continuation.resume(returning: image.jpegData(compressionQuality: 0.8).map(Loaded.data) ?? .nothing)
                #endif
                default: continuation.resume(returning: .nothing)
                }
            }
        }
    }

    func copyFile(at url: URL) throws -> SharedFileData {
        let sharedURL = try manager.copyFileToSharedContainer(from: url)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return SharedFileData(fileURL: sharedURL, fileName: url.lastPathComponent,
                              mimeType: SharedFileData.mimeType(forExtension: url.pathExtension),
                              fileSize: size)
    }

    func copyData(_ data: Data, named name: String) throws -> SharedFileData {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appendingPathComponent(name)
        try data.write(to: file)
        let sharedURL = try manager.copyFileToSharedContainer(from: file)
        return SharedFileData(fileURL: sharedURL, fileName: name,
                              mimeType: SharedFileData.mimeType(forExtension: (name as NSString).pathExtension),
                              fileSize: Int64(data.count))
    }
}
