import XCTest

/// Finding this checkout, and the web checkout beside it.
///
/// Extracted because three test classes had grown their own copy (task 97208a72) — and
/// the copies had already diverged once: the original walked up until the directory was
/// literally named `astrid-ios`, which is never true in a git worktree, so every
/// path-based assertion silently skipped. By 2026-09 a hundred more files had grown a
/// positional `URL(fileURLWithPath: #filePath).deletingLastPathComponent()…` walk whose hop
/// count depended on which folder the file sat in, so this file moved to `TestSupport/`
/// (compiled into both test targets) and grew `root` and `source(at:)`.
enum RepositoryLocator {

    /// The checkout root, resolved once and never throwing.
    ///
    /// Walks up from THIS file looking for `Astrid App.xcodeproj`; if that is not found
    /// (a sandboxed host that cannot stat the tree) it falls back to the positional parent of
    /// `TestSupport/`, which is what every hand-rolled walk used to compute — so a test that
    /// could read the tree before can still read it, and one that could not fails the same way.
    static let root: URL = {
        let here = URL(fileURLWithPath: #filePath)
        var url = here
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Astrid App.xcodeproj").path) {
                return url
            }
        }
        return here.deletingLastPathComponent().deletingLastPathComponent()
    }()

    /// The contents of a tracked file, by repo-relative path.
    static func source(at relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Walk up from a source file to the repository root.
    ///
    /// Identified by `Astrid App.xcodeproj` rather than by the folder's NAME: a git
    /// worktree (or any clone under a different folder name) is not called `astrid-ios`.
    static func repositoryRoot(from filePath: String = #filePath) throws -> URL {
        var url = URL(fileURLWithPath: filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Astrid App.xcodeproj").path) {
                return url
            }
        }
        throw XCTSkip("Repository root not found from \(filePath) — running outside a source checkout")
    }

    /// The paired astrid-web checkout.
    ///
    /// When this repo is a git worktree (`astrid-ios-<topic>`) the matching web worktree
    /// is `astrid-web-<topic>` — prefer it, so a run from a feature worktree checks the
    /// web branch it is paired with rather than whatever happens to be on main. Falls
    /// back to plain `astrid-web`, and skips when neither is present: the web repo is not
    /// required to be cloned.
    ///
    /// Kept in step with `scripts/lib/find-web-repo.sh`, which does the same for the
    /// shell scripts. `BrandProfileTests` asserts the two agree.
    static func siblingWebRepository(from filePath: String = #filePath) throws -> URL {
        let root = try repositoryRoot(from: filePath)
        let parent = root.deletingLastPathComponent()
        let suffix = root.lastPathComponent.hasPrefix("astrid-ios")
            ? String(root.lastPathComponent.dropFirst("astrid-ios".count))
            : ""

        for candidate in ["astrid-web\(suffix)", "astrid-web"] {
            let url = parent.appendingPathComponent(candidate)
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("package.json").path) {
                return url
            }
        }
        throw XCTSkip("No astrid-web checkout beside \(root.lastPathComponent)")
    }
}
