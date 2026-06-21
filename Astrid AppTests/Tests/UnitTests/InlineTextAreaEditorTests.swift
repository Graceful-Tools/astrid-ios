import XCTest
@testable import Astrid_App

/// Unit tests for `InlineTextAreaEditor`'s placeholder/caret alignment.
///
/// SwiftUI's `TextEditor` is backed by a `UITextView` whose text container
/// adds its own insets *inside* any SwiftUI `.padding(...)`: a default
/// `lineFragmentPadding` of 5pt horizontally and a `textContainerInset` of
/// 8pt vertically. Glyphs and the caret therefore render at
/// `containerPadding + UIKit inset`, while a plain `Text` placeholder given
/// the same `.padding(...)` sits at `containerPadding` only — so the
/// placeholder text and the caret visibly disagree (the reported bug).
///
/// `InlineTextAreaMetrics` exists so the placeholder can be offset onto the
/// exact caret/text origin, and so this test can lock the contract.
final class InlineTextAreaEditorTests: XCTestCase {

    /// The placeholder must sit exactly where the TextEditor renders text and
    /// the caret, so the caret lands on the placeholder's first glyph.
    func testPlaceholderOriginMatchesTextEditorTextOrigin() {
        XCTAssertEqual(InlineTextAreaMetrics.placeholderLeadingPadding,
                       InlineTextAreaMetrics.textOriginLeading,
                       "placeholder leading edge must match the TextEditor text origin")
        XCTAssertEqual(InlineTextAreaMetrics.placeholderTopPadding,
                       InlineTextAreaMetrics.textOriginTop,
                       "placeholder top edge must match the TextEditor text origin")
    }

    /// Regression: a naive `.padding(containerPadding)` placeholder ignores the
    /// UITextView's internal insets — that mismatch is the bug being fixed.
    func testPlaceholderIsNotNaiveContainerPadding() {
        XCTAssertNotEqual(InlineTextAreaMetrics.placeholderLeadingPadding,
                          InlineTextAreaMetrics.containerPadding,
                          "placeholder must account for UITextView lineFragmentPadding")
        XCTAssertNotEqual(InlineTextAreaMetrics.placeholderTopPadding,
                          InlineTextAreaMetrics.containerPadding,
                          "placeholder must account for UITextView textContainerInset")
    }

    /// The text origin is the container padding plus the documented UIKit insets.
    func testTextOriginAccountsForUITextViewInsets() {
        XCTAssertEqual(InlineTextAreaMetrics.textOriginLeading,
                       InlineTextAreaMetrics.containerPadding
                       + InlineTextAreaMetrics.textViewHorizontalInset)
        XCTAssertEqual(InlineTextAreaMetrics.textOriginTop,
                       InlineTextAreaMetrics.containerPadding
                       + InlineTextAreaMetrics.textViewVerticalInset)
    }
}
