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

    func testSiblingWebRepoHasV1RoutesIOSConsumes() throws {
        let webRoot = try repositoryRoot()
            .deletingLastPathComponent()
            .appendingPathComponent("astrid-web")

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
            "app/api/v1/sse/route.ts"
        ]

        for route in routeFiles {
            let url = webRoot.appendingPathComponent(route)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing web v1 route: \(route)")
        }
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "astrid-ios" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url
    }
}
