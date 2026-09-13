import Foundation

/// The ownership-transfer half of `AstridAPIClient` (AITD-392).
///
/// An extension for the reason `AstridAPIClient+ListMembers.swift` is one: the client sits
/// exactly on its `SourceFileSizeGuardTests` ceiling, and that ceiling is there to ask "should
/// this still be one file?" rather than to be raised. Two endpoints that belong to each other —
/// the probe and the act — are their own answer.
///
/// An owner cannot simply leave a shared list: ownership is what `canDelete` keys on, so it has
/// to be handed to someone by name. Both routes are `/api/v1`, and the scopes they need
/// (`lists:read`, `lists:manage_members`) are already in the `mobile_app` group.
///
/// `APIEndpointInventoryTests` scans this file too — a path that moved out of the client's main
/// file has not left the app.
extension AstridAPIClient {

    /// Who may this list be handed to?
    ///
    /// Excludes AI-agent members (an agent cannot stand as a list's billing authority), people
    /// with a pending invitation (not members yet) and the owner themselves — the server decides
    /// all three, so the apps do no filtering of their own.
    ///
    /// **An empty array is a 200.** "You have nobody to hand this to" and "you may not do this"
    /// are different states; the 403 is what says the latter. See `ListOwnershipTransfer`.
    func eligibleNewOwners(listId: String) async throws -> [User] {
        struct EligibleOwnersResponse: Codable {
            let eligibleOwners: [User]
        }
        let response: EligibleOwnersResponse = try await request(
            method: "GET",
            path: "/api/v1/lists/\(listId)/transfer-ownership"
        )
        return response.eligibleOwners
    }

    /// Hand the list to `newOwnerId` and leave it, in ONE call.
    ///
    /// The server does both in a single transaction: `ownerId` moves, the new owner's member row
    /// goes (they are the owner now) and the caller's row goes. So there is no window where the
    /// transfer landed and the leave did not — and **no `leaveList` afterwards**, which would be
    /// a second call against a list the caller is no longer a member of.
    func transferListOwnership(listId: String, newOwnerId: String) async throws {
        struct TransferRequest: Codable { let newOwnerId: String }
        struct TransferResponse: Codable { let message: String? }
        let _: TransferResponse = try await request(
            method: "POST",
            path: "/api/v1/lists/\(listId)/transfer-ownership",
            body: TransferRequest(newOwnerId: newOwnerId)
        )
    }
}
