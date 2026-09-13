//  ListOwnershipTransfer.swift
//  Whether the owner of a list can hand it to someone, and to whom. (Task AITD-392)
//
//  `ListMembershipRoster.leaveOption` answers "may this person leave, and on what terms" from the
//  list alone, and for an owner the answer is always `.transferOwnership`. It cannot answer the
//  next question — WHO — because that lives on the server: an owner with no other human members
//  has nobody to hand the list to, and only the server knows who is eligible.
//
//  So the GET is the probe, and it has four meaningfully different answers. The point of this
//  type is that they stay four rather than collapsing into "worked" and "didn't":
//
//  - people came back          → offer the picker
//  - the list came back EMPTY  → "you may, but there is nobody yet". A 200, not an error; the
//                                v1 contract is explicit that an empty array is success.
//  - 403                       → not the owner. The server, not the client, decides this.
//  - 404 or unreachable        → the route is not deployed yet. astrid-web does not auto-deploy,
//                                so a build can reach a server that has never heard of this
//                                endpoint, and the honest thing to show is the "use the web app"
//                                line this feature replaces — not a broken button.
//
//  That last case is why the control can ship before the web deploy lands: it appears exactly
//  when the endpoint does, with no flag to flip afterwards.
//
//  Pure — no view, no network — so the interesting decision is testable on its own.

import Foundation

enum ListOwnershipTransfer {

    /// What the leave control should offer an owner right now.
    enum Availability: Equatable {
        /// The route is not deployed, or the network failed. Show the existing explanation.
        case unavailable
        /// The server says this caller is not the owner. Show nothing.
        case notPermitted
        /// The caller may transfer, but there is nobody eligible to receive it.
        case noEligibleOwners
        /// Hand the list to one of these.
        case available([User])
    }

    /// Read the probe.
    ///
    /// Takes the result rather than performing it so the mapping can be asserted without a
    /// server: this is the whole decision, and it is the part that is easy to get wrong.
    static func availability(from result: Result<[User], Error>) -> Availability {
        switch result {
        case .success(let owners):
            // An empty array is a 200. "Nobody to hand it to" and "you may not do this" are
            // different states and want different UI — the v1 contract says so explicitly.
            return owners.isEmpty ? .noEligibleOwners : .available(owners)

        case .failure(let error):
            guard case AstridAPIError.httpError(let statusCode, _) = error else {
                // A transport failure is indistinguishable from an undeployed route from here,
                // and both mean the same thing to the user: not now, use the web app.
                return .unavailable
            }
            switch statusCode {
            case 403: return .notPermitted
            default: return .unavailable
            }
        }
    }
}
