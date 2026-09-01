//  CachedImageLoaderURLChangeTests.swift
//  Regression guard for Task 16f39f36 — "[mac] update list image doesn't optimistically update and
//  maybe doesn't update the list icon on mac".
//
//  The optimistic write was never the problem: the new image is applied to the in-memory list and
//  to Core Data before the request goes out. The problem was that nothing REDREW.
//
//  `CachedAsyncImage` captured its URL once, in `init`, into a `@StateObject` loader, and fetched
//  only from `.onAppear`. SwiftUI does not re-run a `@StateObject`'s initial value when a property
//  changes, so an on-screen image view stayed pinned to the URL it was born with. Roughly
//  twenty-five call sites construct one and exactly one of them (`MacListIcon`) remembered the
//  `.id(url)` workaround — so this was quietly wrong nearly everywhere a picture can change:
//  list images, avatars after a profile photo change, an assignee swapped on a row.
//
//  Note the asymmetry that made it look intermittent: none → image WORKS, because that path makes
//  the image view appear for the first time and `onAppear` fires. Only image → different image
//  fails. The tests below cover the failing direction explicitly.

import XCTest
import SwiftUI
@testable import Astrid_App

@MainActor
final class CachedImageLoaderURLChangeTests: XCTestCase {

    private let urlA = URL(string: "https://example.test/images/placeholders/lavender.png")!
    private let urlB = URL(string: "https://example.test/images/placeholders/coral.png")!

    /// Distinguishable solid-colour images, so "did it actually swap" is answerable.
    private func image(_ color: PlatformColor, size: CGFloat = 4) -> PlatformImage {
        #if os(macOS)
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        color.drawSwatch(in: NSRect(x: 0, y: 0, width: size, height: size))
        img.unlockFocus()
        return img
        #else
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        #endif
    }

    /// Whole-file bytes, not a prefix: two solid PNGs of the same size share an identical header,
    /// so comparing the first N bytes would call two different pictures equal.
    private func bytes(_ image: PlatformImage) throws -> Data {
        try XCTUnwrap(image.pngDataCompat())
    }

    override func setUp() async throws {
        try await super.setUp()
        ImageCache.shared.remove(url: urlA)
        ImageCache.shared.remove(url: urlB)
    }

    override func tearDown() async throws {
        ImageCache.shared.remove(url: urlA)
        ImageCache.shared.remove(url: urlB)
        try await super.tearDown()
    }

    /// The bug, at the level it actually lives: ask the loader for a different picture and you must
    /// get the different picture. Both are pre-seeded in the cache, so this needs no network and
    /// resolves synchronously.
    func testLoadingADifferentURLYieldsTheDifferentImage() throws {
        ImageCache.shared.set(image(.red), for: urlA)
        ImageCache.shared.set(image(.blue, size: 8), for: urlB)

        // Both must be cache hits, or this test would be measuring the network instead of the bug.
        XCTAssertNotNil(ImageCache.shared.get(url: urlA))
        XCTAssertNotNil(ImageCache.shared.get(url: urlB))

        let loader = CachedImageLoader(url: urlA)
        loader.load(url: urlA)
        let first = try bytes(try XCTUnwrap(loader.image, "the first image should resolve from cache"))

        loader.load(url: urlB)
        let second = try bytes(try XCTUnwrap(loader.image, "re-pointing must produce an image"))

        XCTAssertNotEqual(first, second,
                          "The loader stayed on the URL it was born with — this is the list image "
                          + "that would not change, and every avatar that would not change either")
    }

    /// Re-pointing at a URL that is NOT cached must not keep showing the old picture while the new
    /// one loads. Showing the previous list's image under the new list's name is worse than showing
    /// the placeholder for a moment.
    func testARepointToAnUncachedURLClearsTheStaleImage() throws {
        ImageCache.shared.set(image(.red), for: urlA)

        let loader = CachedImageLoader(url: urlA)
        loader.load(url: urlA)
        XCTAssertNotNil(loader.image)

        loader.load(url: urlB)   // never cached; the network fetch will fail against example.test
        XCTAssertNil(loader.image,
                     "The stale image must be dropped so the placeholder shows while loading")
    }

    /// Asking for the SAME url again must not throw away an image we already have — that would
    /// flicker every list row on each redraw.
    func testReloadingTheSameURLKeepsTheImage() throws {
        ImageCache.shared.set(image(.red), for: urlA)

        let loader = CachedImageLoader(url: urlA)
        loader.load(url: urlA)
        let before = try bytes(try XCTUnwrap(loader.image))

        loader.load(url: urlA)
        let after = try bytes(try XCTUnwrap(loader.image, "an idempotent reload must not blank it"))
        XCTAssertEqual(before, after)
    }

    /// The component must not go back to relying on call sites remembering `.id(url)`. It reacts to
    /// a changed url itself, for every one of the ~25 places that build one.
    func testTheViewReactsToAChangedURLItself() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Utilities/ImageCache.swift"), encoding: .utf8)
        let view = try XCTUnwrap(source.components(separatedBy: "struct CachedAsyncImage").last)
        XCTAssertTrue(view.contains("onChange(of: url)") || view.contains("task(id: url)"),
                      "CachedAsyncImage must follow its url, not capture it once in init")
    }

    /// Tasks be508751 / 2f1ec1af: the Copilot endpoint serves SVG without a file extension.
    /// PlatformImage cannot decode it, so the shared image view must choose the bundled mascot.
    func testTasks_be508751_2f1ec1afCopilotEndpointUsesBundledMascot() {
        let url = URL(string: "https://astrid.cc/api/v1/agent-icon/copilot")!
        let user = User(
            id: "copilot", email: "copilot@astrid.cc", name: "GitHub Copilot Agent",
            image: url.absoluteString, isAIAgent: true, aiAgentType: "copilot_agent")

        XCTAssertEqual(AgentAvatarAsset.assetName(for: url), "ai-copilot")
        XCTAssertEqual(user.agentBrandImageAsset, "ai-copilot")
    }
}
