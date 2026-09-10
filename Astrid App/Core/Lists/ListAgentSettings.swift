import Foundation

/// What a per-list AI-agent change SENDS, in one place for both platforms (AITD-380).
///
/// The server does not patch this config field by field. `PUT /api/v1/lists/[id]`
/// takes the `aiAgentConfig` it is given and replaces the stored value with it
/// (`storedAgentConfig` → `normalizeAgentEnabledConfig`, astrid-web
/// `app/api/v1/lists/[id]/route.ts`), and an absent `enabledTypes` normalizes to
/// `[]`. So a client that sends only the field it changed **erases the fields it
/// left out** — change the default agent naively and the list's enabled types are
/// gone, with a 200 and no error anywhere.
///
/// Web carries the current types forward by hand at its one call site
/// (`components/list-admin/ListAiAgentSection.tsx`). That line is the real
/// contract, and a rule each platform has to remember separately is one a
/// platform eventually forgets — so it lives here, and the views ask for it.
///
/// Pure logic: no network, no service, no UI. `ListService.setListDefaultAgent`
/// is the Canonical Control Point that actually writes (ASTRID.md §0 rule 1).
enum ListAgentSettings {

    /// The list's enabled agent types as they stand now.
    ///
    /// The config object is authoritative when present — including when it says
    /// `[]`, which is a real answer and must not fall through to a stale array.
    /// The bare `aiAgentsEnabled` array is the fallback: it is what the wire
    /// carries (`serializeListAgentFields`), and a list cached before the object
    /// form was served has only that.
    static func enabledTypes(on list: TaskList) -> [String] {
        list.aiAgentConfig?.enabledTypes ?? list.aiAgentsEnabled ?? []
    }

    /// The agent currently chosen for this list, or nil for "use account default".
    ///
    /// An empty string reads as nil rather than as an agent whose id is "": the
    /// picker tags its account-default row with `""`, and a round-trip can store
    /// that. Treating the two differently leaves the picker with nothing selected.
    static func currentDefaultAgentId(on list: TaskList) -> String? {
        guard let id = list.aiAgentConfig?.defaultAgentId, !id.isEmpty else { return nil }
        return id
    }

    /// The full config to send when changing ONLY the default agent — the
    /// existing types carried through unchanged.
    ///
    /// Nil `agentId` means "use the account default", and travels as an omitted
    /// key: the server normalizes an absent `defaultAgentId` to null, which is
    /// what clears it.
    static func settingDefaultAgent(_ agentId: String?, on list: TaskList) -> ListAgentConfig {
        ListAgentConfig(
            enabledTypes: enabledTypes(on: list),
            defaultAgentId: (agentId?.isEmpty ?? true) ? nil : agentId
        )
    }

    /// The PUT body for that change. Every other field stays nil so the encoder
    /// omits it — the server applies what it is given, so a field named here
    /// would overwrite something the user never touched.
    static func updateRequest(settingDefaultAgent agentId: String?,
                              on list: TaskList) -> UpdateListRequest {
        var request = UpdateListRequest()
        request.aiAgentConfig = settingDefaultAgent(agentId, on: list)
        return request
    }
}
