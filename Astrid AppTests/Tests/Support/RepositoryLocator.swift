import XCTest

/// Finding this checkout, and the web checkout beside it.
///
/// Extracted because three test classes had grown their own copy (task 97208a72) — and
/// the copies had already diverged once: the original walked up until the directory was
/// literally named `astrid-ios`, which is never true in a git worktree, so every
/// path-based assertion silently skipped.
enum RepositoryLocator {

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
