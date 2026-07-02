import XCTest
@testable import Astrid_App

/// Regression: with the Outbox authoritative, the upload→comment dependency
/// chain OWNS every staged attachment. The legacy upload paths (pull-to-refresh,
/// network-restore observer, launch auto-retry) must not touch them — the legacy
/// uploader deletes the local file after upload, which starves the chain's
/// upload entry ("local file missing" → permanent → the comment strands and the
/// first of two online photo comments disappeared).
final class AttachmentUploadPolicyTests: XCTestCase {

    private let statuses: [String: PendingAttachment.UploadStatus] = [
        "temp_a": .pending,
        "temp_b": .failed,
        "temp_c": .completed,
        "temp_d": .uploading,
    ]

    func testNoLegacyCandidatesWhenOutboxAuthoritative() {
        XCTAssertEqual(
            AttachmentUploadPolicy.legacyUploadCandidates(statuses: statuses, outboxAuthoritative: true),
            [],
            "chain-owned pending uploads must never be picked up by legacy sync"
        )
    }

    func testLegacyCandidatesArePendingAndFailedWhenLegacyMode() {
        let ids = AttachmentUploadPolicy.legacyUploadCandidates(statuses: statuses, outboxAuthoritative: false)
        XCTAssertEqual(Set(ids), ["temp_a", "temp_b"],
                       "legacy mode retries pending + failed, skips completed/uploading")
    }
}
