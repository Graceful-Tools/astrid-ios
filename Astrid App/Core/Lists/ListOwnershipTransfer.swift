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
//  The decision is astrid-core's (`services::list::transfer_availability`); this is its shape.

import Foundation

enum ListOwnershipTransfer {

    /// astrid-core's `TransferAvailability` — the core reads the probe (its
    /// `transfer_availability`, tested there); this is what the leave control draws from.
    enum Availability: Equatable, Decodable {
        case unavailable
        case notPermitted
        case noEligibleOwners
        case available([User])

        private enum Keys: String, CodingKey { case availability, owners }

        init(from decoder: Decoder) throws {
            let answer = try decoder.container(keyedBy: Keys.self)
            switch try answer.decode(String.self, forKey: .availability) {
            case "notPermitted": self = .notPermitted
            case "noEligibleOwners": self = .noEligibleOwners
            case "available": self = .available(try answer.decode([User].self, forKey: .owners))
            default: self = .unavailable
            }
        }
    }
}
