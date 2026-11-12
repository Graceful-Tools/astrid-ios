//  AccountCoreTests.swift
//  The account screen's delete, export, resend-verification and email change go through
//  astrid-core (AITD-620, third slice): the commands it sends, and the refusals the core makes
//  before any request.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests (`dispatch/tests/account.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class AccountCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var core: CoreSession { AppCore.shared.session }

    // MARK: Deleting — the contract phrase, not the typed one

    /// Regression (AITD-620): the iOS screen sent the phrase as the person typed it in their own
    /// language ("MEIN KONTO LÖSCHEN") and the Mac sent "DELETE", but the server accepts only
    /// "DELETE MY ACCOUNT", so deletion failed everywhere but English iOS.
    func testADeleteSendsTheContractPhraseWhateverTheLanguage_AITD620() throws {
        let sent = try json(AccountCommands.delete())
        XCTAssertEqual(sent["kind"] as? String, "deleteAccount")
        XCTAssertEqual(sent["confirmation"] as? String, "DELETE MY ACCOUNT")
        XCTAssertNotEqual(AccountCommands.deletionConfirmation, "MEIN KONTO LÖSCHEN")
    }

    /// The core refuses a wrong phrase with `badRequest` before any request; the one sent passes
    /// that check (and then fails only for want of a network in the unit host).
    func testTheCoreAcceptsThePhraseSentAndRefusesALocalizedOne_AITD620() async throws {
        var localized = CoreCommand(kind: "deleteAccount")
        localized.set("confirmation", "MEIN KONTO LÖSCHEN")
        do {
            try await core.run(localized)
            XCTFail("a phrase the server would refuse never reaches it")
        } catch let failure as CoreFailure {
            XCTAssertEqual(failure.kind, .badRequest)
        }

        do {
            try await core.run(AccountCommands.delete())
            XCTFail("the unit host has no server to delete an account on")
        } catch let failure as CoreFailure {
            XCTAssertNotEqual(failure.kind, .badRequest, "the contract phrase passed: \(failure)")
        }
    }

    // MARK: The other commands

    func testAnExportNamesTheFormatAndTheFileTheCoreWritesTo_AITD620() throws {
        let file = URL(fileURLWithPath: "/tmp/export.csv")
        let sent = try json(AccountCommands.export(format: "csv", to: file))
        XCTAssertEqual(sent["kind"] as? String, "exportAccount")
        XCTAssertEqual(sent["format"] as? String, "csv")
        XCTAssertEqual(sent["path"] as? String, "/tmp/export.csv")
    }

    func testResendAndChangeEmailAreTheCoresCommands_AITD620() throws {
        XCTAssertEqual(try json(AccountCommands.resendVerification())["kind"] as? String, "resendVerification")
        let change = try json(AccountCommands.changeEmail("ada@example.com"))
        XCTAssertEqual(change["kind"] as? String, "changeEmail")
        XCTAssertEqual(change["email"] as? String, "ada@example.com")
    }

    /// Name and photo (AITD-620, slice 13): the screens upload a photo the moment it is picked and
    /// hold its address, so `updateProfile` carries that `image`, never a `photoPath` the core
    /// would upload a second time.
    func testAProfileUpdateCarriesTheNameAndTheUploadedPhotosAddress_AITD620() throws {
        let sent = try json(AccountCommands.updateProfile(name: "Ada", image: "https://blob.test/ada.png"))
        XCTAssertEqual(sent["kind"] as? String, "updateProfile")
        XCTAssertEqual(sent["name"] as? String, "Ada")
        XCTAssertEqual(sent["image"] as? String, "https://blob.test/ada.png")
        XCTAssertNil(sent["photoPath"], "the photo is already uploaded")
    }

    func testAPhotoOnlyUpdateSendsNoName_AITD620() throws {
        let sent = try json(AccountCommands.updateProfile(name: nil, image: "https://blob.test/ada.png"))
        XCTAssertTrue(sent["name"] == nil || sent["name"] is NSNull, "\(sent)")
    }

    func testSendAndCancelVerificationAreTheCoresCommands_AITD620() throws {
        XCTAssertEqual(try json(AccountCommands.sendVerification())["kind"] as? String, "sendVerification")
        XCTAssertEqual(try json(AccountCommands.cancelVerification())["kind"] as? String, "cancelVerification")
    }

    func testAnEmailChangeAnswerReadsWhetherVerificationIsNeeded_AITD620() throws {
        let answer = try CoreJSON.answer(
            #"{"ok":true,"value":{"verificationRequired":true,"message":"Check your inbox"}}"#,
            as: EmailChangeResult.self)
        XCTAssertEqual(answer, EmailChangeResult(verificationRequired: true, message: "Check your inbox"))
    }

    // MARK: Refused before any request, and shown in the core's words

    func testAMalformedAddressIsRefusedByTheCoreWithASentence_AITD620() async throws {
        do {
            _ = try await AccountService.shared.updateAccount(UpdateAccountRequest(email: "not-an-address"))
            XCTFail("an address the core can reject never reaches the server")
        } catch let failure as CoreFailure {
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertEqual(AccountService.message(for: failure), failure.message)
        }
    }

    func testAnOrdinaryErrorStillShowsItsOwnDescription_AITD620() {
        let error = AstridAPIError.unauthorized
        XCTAssertEqual(AccountService.message(for: error), error.localizedDescription)
    }
}
