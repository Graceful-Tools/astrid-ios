import Foundation

/// The list-membership half of `AstridAPIClient` (AITD-388).
///
/// Split out because the client had grown onto the `SourceFileSizeGuardTests` ratchet and sat
/// exactly on its ceiling — twice in one day a new endpoint could not be added without raising
/// the number. Raising it again would have been the reflex that guard exists to catch; the
/// ceiling is meant to ask "should this file still be one file?", and for a coherent group of
/// six endpoints the answer is no.
///
/// An extension, so every call site is unchanged and `AstridAPIClient.shared` is still the one
/// client. `APIEndpointInventoryTests` scans this file too — a path that moved out of the
/// client's main file has not left the app.
extension AstridAPIClient {

    /// Get all members of a list
    func getListMembers(listId: String) async throws -> ListMembersResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/lists/\(listId)/members"
        )
    }

    /// Add a member to a list
    func addListMember(listId: String, email: String, role: String = "member") async throws -> AddMemberResponse {
        struct AddMemberRequest: Codable {
            let email: String
            let role: String
        }

        let body = AddMemberRequest(email: email, role: role)

        return try await request(
            method: "POST",
            path: "/api/v1/lists/\(listId)/members",
            body: body
        )
    }

    /// Update a member's role
    func updateListMember(listId: String, userId: String, role: String) async throws -> UpdateMemberResponse {
        struct UpdateMemberRoleRequest: Codable {
            let role: String
        }

        let body = UpdateMemberRoleRequest(role: role)

        return try await request(
            method: "PUT",
            path: "/api/v1/lists/\(listId)/members/\(userId)",
            body: body
        )
    }

    /// Remove a member from a list
    func removeListMember(listId: String, userId: String) async throws -> DeleteResponse {
        return try await request(
            method: "DELETE",
            path: "/api/v1/lists/\(listId)/members/\(userId)"
        )
    }

    /// Cancel a pending invitation
    func cancelInvitation(listId: String, email: String) async throws -> DeleteResponse {
        struct CancelInvitationRequest: Codable {
            let email: String
        }
        return try await request(
            method: "DELETE",
            path: "/api/v1/lists/\(listId)/invitations",
            body: CancelInvitationRequest(email: email)
        )
    }

    /// Change a pending invitation's role before it is accepted.
    ///
    /// Addressed by EMAIL on the invitation resource, not by `/members/{userId}` — an unaccepted
    /// invitation has no userId, and there may not even be an account yet. Same shape as
    /// `cancelInvitation`, and the same route Web uses.
    func updateInvitationRole(listId: String, email: String, role: String) async throws -> UpdateMemberResponse {
        struct UpdateInvitationRequest: Codable {
            let email: String
            let role: String
        }
        return try await request(
            method: "PUT",
            path: "/api/v1/lists/\(listId)/invitations",
            body: UpdateInvitationRequest(email: email, role: role)
        )
    }
}
