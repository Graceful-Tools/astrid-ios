import Foundation

/// Whether typed text is worth sending as an email address — the check that enables the button
/// while someone types, not a validator. The server decides what is deliverable.
///
/// One home for a rule that lived in four views (AITD-538): the passkey sign-up sheet on iOS and
/// Mac, the Mac invite field and the assign-by-email row. They had drifted — the iOS sheet did not
/// trim, so a trailing space from autocomplete was sent as part of the address.
nonisolated enum EmailAddress {
    /// The text as it should be sent: surrounding spaces dropped.
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    static func isPlausible(_ text: String) -> Bool {
        let address = trimmed(text)
        return address.contains("@") && address.contains(".")
    }
}
