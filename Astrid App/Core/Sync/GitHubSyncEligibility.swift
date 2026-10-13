import Foundation

/// Which lists the ON-DEVICE GitHub Issues engine may touch (AITD-491, spec §11.3).
///
/// A GitHub Projects-backed list is already mirrored by the server: astrid.cc owns the issue and
/// writes it through its `github_project` backend. This device's Issues engine is a second writer
/// on the same issue — it PATCHes title, body and state from its own watermarks and closes the
/// twin when the task completes — so two engines would overwrite each other's edits and reopen
/// what the other had closed. The engine therefore stays off for those lists, and every classic
/// list keeps syncing exactly as before.
///
/// The rule lives here, once, because it is read in two places that must not drift: the pass
/// itself, and the picker that offers a list to link.
enum GitHubSyncEligibility {
    /// The subset of `links` this device may sync.
    ///
    /// A link whose list is not loaded yet is KEPT: the list cache can be empty while the links
    /// are already in hand (launch, a cold sign-in), and refusing an unknown list would silently
    /// stop a classic account's sync. A list the user has just bound to a project is known before
    /// any pass of its own can run, because binding it reloads the lists.
    static func syncableLinks(_ links: [ExternalListLinkDTO], in lists: [TaskList]) -> [ExternalListLinkDTO] {
        let backed = Set(lists.filter { $0.isGitHubBacked }.map { $0.id })
        guard !backed.isEmpty else { return links }
        return links.filter { !backed.contains($0.astridListId) }
    }

    /// The lists the repo picker may offer — a real list the user can mirror. A GitHub-backed list
    /// is absent, so the link cannot be made in the first place; virtual lists and board columns
    /// were never offered.
    static func linkableLists(_ lists: [TaskList]) -> [TaskList] {
        lists.filter { !($0.isVirtual ?? false) && !$0.isStatusList && !$0.isGitHubBacked }
    }
}
