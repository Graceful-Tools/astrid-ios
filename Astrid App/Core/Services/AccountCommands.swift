import AstridCore
import Foundation

/// The astrid-core commands behind the account screen (AITD-620): delete, export, name and photo,
/// send, resend and cancel the verification mail, and change the email address.
///
/// The paths and wire names are the core's (`services/account.rs`); this only spells the commands,
/// so `AccountService` stays a face and the spelling is testable without a server.
enum AccountCommands {
    /// The phrase the server and the core require, exactly (`ACCOUNT_DELETION_CONFIRMATION_PHRASE`
    /// on the web, `DELETE_CONFIRMATION` in the core). It is a wire constant, not copy: the person
    /// types their own language's phrase (`settings.account.delete_confirm_phrase`, or `DELETE` on
    /// the Mac) as the guard, and this is what is sent once they have. Sending the typed phrase is
    /// how deletion came to fail in every language but English, and always on the Mac.
    static let deletionConfirmation = "DELETE MY ACCOUNT"

    static func delete() -> CoreCommand {
        var command = CoreCommand(kind: "deleteAccount")
        command.set("confirmation", deletionConfirmation)
        return command
    }

    /// The core writes the export straight to `path` rather than carrying megabytes back as JSON.
    static func export(format: String, to path: URL) -> CoreCommand {
        var command = CoreCommand(kind: "exportAccount")
        command.set("format", format)
        command.set("path", path.path)
        return command
    }

    static func resendVerification() -> CoreCommand {
        CoreCommand(kind: "resendVerification")
    }

    /// Send the verification mail for the account's address. Answers `{ message }`.
    static func sendVerification() -> CoreCommand {
        CoreCommand(kind: "sendVerification")
    }

    /// Withdraw a pending email change. Answers `{ message }`.
    static func cancelVerification() -> CoreCommand {
        CoreCommand(kind: "cancelVerification")
    }

    /// Name and photo. The screens upload a photo the moment it is picked and hold its address,
    /// so this carries `image` (put on the account as it is), never the core's `photoPath`, which
    /// would upload it a second time. The core refuses both at once before any request.
    static func updateProfile(name: String?, image: String?) -> CoreCommand {
        var command = CoreCommand(kind: "updateProfile")
        command.set("name", name)
        command.set("image", image)
        return command
    }

    /// The address only changes once the link in the mail is followed; the core answers
    /// `{ verificationRequired, message }`.
    static func changeEmail(_ email: String) -> CoreCommand {
        var command = CoreCommand(kind: "changeEmail")
        command.set("email", email)
        return command
    }
}

/// `changeEmail`'s answer.
struct EmailChangeResult: Decodable, Equatable {
    let verificationRequired: Bool
    let message: String?
}

/// The answer to `sendVerification`, `resendVerification` and `cancelVerification`: the server's
/// sentence.
struct VerificationResent: Decodable, Equatable {
    let message: String?
}
