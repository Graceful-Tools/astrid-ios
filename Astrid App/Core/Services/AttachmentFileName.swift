//  AttachmentFileName.swift
//  The single place that turns an attachment's *claimed* name into a path we are willing to write.
//
//  Task c6468c5c (AITD-312). `Attachment.name` and `SecureFile.name` are decoded straight from the
//  API, and the upload route validates the extension/MIME pair rather than the path — so a member
//  of a shared list can name a file "../../Library/Application Support/store.png" and have it pass.
//  Seven call sites used to join that name onto a temp directory, one of them removing the target
//  before copying onto it. Tapping the attachment ran the traversal.
//
//  Both platforms use this: it lives in Core/ so the Mac target picks it up from the same
//  synchronized group, and Mac must not grow its own copy (ASTRID.md §9).

import Foundation

enum AttachmentFileName {

    /// Used when the claimed name carries no usable leaf at all ("", "/", ".", "..").
    static let fallbackName = "attachment"

    /// The longest leaf we will write. HFS+/APFS cap a name at 255 bytes; going over turns a
    /// preview into a write failure.
    private static let maxNameBytes = 255

    /// Reduce a claimed attachment name to a single, safe filename component.
    ///
    /// The name keeps its extension wherever one survives — QuickLook picks its previewer from the
    /// extension, so stripping it would trade a security bug for a broken preview.
    static func sanitized(_ rawName: String) -> String {
        // Only the final component can ever be a filename, so "../../x.png" becomes "x.png".
        var leaf = (rawName as NSString).lastPathComponent

        // `lastPathComponent` preserves "." and ".." verbatim, and leaves a bare "/" as "/".
        leaf = leaf.replacingOccurrences(of: "/", with: "_")
        leaf = leaf.replacingOccurrences(of: "\u{0}", with: "_")
        leaf = leaf.trimmingCharacters(in: .whitespacesAndNewlines)

        if leaf.isEmpty || leaf == "." || leaf == ".." || leaf.allSatisfy({ $0 == "_" }) {
            return fallbackName
        }

        return capped(leaf)
    }

    /// A URL for `rawName` that is guaranteed to sit directly inside `directory`.
    ///
    /// This is the call site API — nothing should call `appendingPathComponent` with a name that
    /// came off the wire. The containment check is belt-and-braces over `sanitized`: if a future
    /// edit weakens the sanitiser, the URL degrades to the fallback leaf rather than escaping.
    static func temporaryURL(in directory: URL, for rawName: String) -> URL {
        let candidate = directory.appendingPathComponent(sanitized(rawName))
        guard contains(directory, candidate) else {
            return directory.appendingPathComponent(fallbackName)
        }
        return candidate
    }

    // MARK: - Internals

    private static func contains(_ directory: URL, _ candidate: URL) -> Bool {
        var base = directory.standardizedFileURL.path
        if !base.hasSuffix("/") { base += "/" }
        let resolved = candidate.standardizedFileURL.path
        return resolved.hasPrefix(base) && resolved != base
    }

    /// Trim the *stem* rather than the tail, so the extension survives an overlong name.
    private static func capped(_ leaf: String) -> String {
        guard leaf.utf8.count > maxNameBytes else { return leaf }

        let name = leaf as NSString
        let ext = name.pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        // A pathological extension can be longer than the budget on its own; fall back then.
        guard suffix.utf8.count < maxNameBytes else { return fallbackName }

        var stem = name.deletingPathExtension
        let budget = maxNameBytes - suffix.utf8.count
        while stem.utf8.count > budget, !stem.isEmpty {
            stem.removeLast()
        }
        return stem.isEmpty ? fallbackName : stem + suffix
    }
}
