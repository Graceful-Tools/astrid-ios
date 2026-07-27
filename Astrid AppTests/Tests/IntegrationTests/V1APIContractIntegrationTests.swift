import XCTest

/// Repository-level contract checks for the iOS client and the sibling web
/// server. These do not hit the network; they verify that the v1 server route
/// files iOS depends on exist and that the iOS API client points at v1 paths.
final class V1APIContractIntegrationTests: XCTestCase {

    func testIOSClientUsesV1ForCoreServiceEndpoints() throws {
        let root = try repositoryRoot()
        let clientURL = root.appendingPathComponent("Astrid App/Core/Networking/AstridAPIClient.swift")
        let source = try String(contentsOf: clientURL)

        let expectedPaths = [
            "/api/v1/tasks",
            "/api/v1/lists",
            "/api/v1/tasks/\\(taskId)/comments",
            "/api/v1/chat/channels",
            "/api/v1/users/me/settings",
            "/api/v1/users/me/smart-tasks",
            "/api/v1/users/me/my-tasks-preferences",
            "/api/v1/users/me/available-agents",
            "/api/v1/users/me/ai-preferences",
            "/api/v1/shortcodes"
        ]

        for path in expectedPaths {
            XCTAssertTrue(source.contains(path), "AstridAPIClient should use \(path)")
        }

        let legacyCorePaths = [
            #"path: "/api/tasks"#,
            #"path: "/api/lists"#,
            #"path: "/api/chat"#,
            #"path: "/api/user/settings"#,
            #"path: "/api/user/my-tasks-preferences"#
        ]

        for path in legacyCorePaths {
            XCTAssertFalse(source.contains(path), "Core iOS service endpoint should not use legacy \(path)")
        }
    }

    /// The atomic Create Board flow must hit the single-request v1 endpoint
    /// `POST /api/v1/projects/from-list` rather than the old two-step
    /// project-then-list-PUT flow that could orphan a project.
    func testCreateBoardUsesAtomicV1Endpoint() throws {
        let root = try repositoryRoot()
        let clientURL = root.appendingPathComponent("Astrid App/Core/Networking/AstridAPIClient.swift")
        let source = try String(contentsOf: clientURL)
        XCTAssertTrue(source.contains("/api/v1/projects/from-list"),
                      "client should call the atomic /api/v1/projects/from-list endpoint")
    }

    /// `resolveShortcode` was the one core endpoint still on a non-v1 path
    /// (`api/shortcodes/<code>`). It must use the v1 path like every other
    /// service call, and must not retain the legacy unversioned form.
    func testResolveShortcodeUsesV1Path() throws {
        let root = try repositoryRoot()
        let clientURL = root.appendingPathComponent("Astrid App/Core/Networking/AstridAPIClient.swift")
        let source = try String(contentsOf: clientURL)

        XCTAssertTrue(source.contains("/api/v1/shortcodes/\\(code)"),
                      "resolveShortcode should request the v1 shortcode path")
        XCTAssertFalse(source.contains("\"api/shortcodes/"),
                       "resolveShortcode must not use the legacy non-v1 shortcode path")
    }

    func testSiblingWebRepoHasV1RoutesIOSConsumes() throws {
        let webRoot = try siblingWebRepository()

        let routeFiles = [
            "app/api/v1/tasks/route.ts",
            "app/api/v1/tasks/[id]/route.ts",
            "app/api/v1/tasks/[id]/comments/route.ts",
            "app/api/v1/lists/route.ts",
            "app/api/v1/lists/[id]/route.ts",
            "app/api/v1/chat/channels/route.ts",
            "app/api/v1/chat/channels/[channelId]/messages/route.ts",
            "app/api/v1/users/me/settings/route.ts",
            "app/api/v1/users/me/smart-tasks/route.ts",
            "app/api/v1/users/me/my-tasks-preferences/route.ts",
            "app/api/v1/users/me/available-agents/route.ts",
            "app/api/v1/users/me/ai-preferences/route.ts",
            "app/api/v1/shortcodes/route.ts",
            "app/api/v1/shortcodes/[code]/route.ts",
            "app/api/v1/projects/from-list/route.ts",
            "app/api/v1/sse/route.ts"
        ]

        for route in routeFiles {
            let url = webRoot.appendingPathComponent(route)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing web v1 route: \(route)")
        }
    }

    /// Locate the paired astrid-web checkout next to this one.
    ///
    /// When the iOS repo is checked out as a git worktree (`astrid-ios-<topic>`), the
    /// matching web worktree is `astrid-web-<topic>` — prefer that, so a contract test
    /// run from a feature worktree checks the web branch it is paired with rather than
    /// whatever happens to be on main. Falls back to plain `astrid-web`, and skips when
    /// neither is present (the web repo is not required to be cloned). Task 97208a72.
    private func siblingWebRepository() throws -> URL {
        let root = try repositoryRoot()
        let parent = root.deletingLastPathComponent()
        let suffix = root.lastPathComponent.hasPrefix("astrid-ios")
            ? String(root.lastPathComponent.dropFirst("astrid-ios".count))
            : ""

        let candidates = ["astrid-web\(suffix)", "astrid-web"]
        for candidate in candidates {
            let url = parent.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("package.json").path) {
                return url
            }
        }

        throw XCTSkip("No astrid-web checkout beside \(root.lastPathComponent) — skipping contract check")
    }

    /// Walk up from this source file to the repository root.
    ///
    /// Identified by the presence of `Astrid App.xcodeproj` rather than by the
    /// checkout being named `astrid-ios`. A git worktree (or any clone under a
    /// different folder name) is not called `astrid-ios`, so the old name check
    /// walked all the way to `/` and every path-based assertion here failed.
    /// Task 97208a72.
    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            let marker = url.appendingPathComponent("Astrid App.xcodeproj")
            if FileManager.default.fileExists(atPath: marker.path) {
                return url
            }
        }
        throw XCTSkip("Repository root not found from \(#filePath) — running outside a source checkout")
    }
}
