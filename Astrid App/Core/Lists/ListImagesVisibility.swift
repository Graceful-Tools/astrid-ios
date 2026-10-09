import Combine
import Foundation

/// Whether list images are drawn — the hide_list_images A/B test (AITD-468).
///
/// Web runs the experiment (astrid-web `lib/list-images-visibility.ts`); this reads the same two
/// inputs so a user is in the same arm on every device: `hide_list_images` from
/// GET /api/v1/features, and `showListImages` from GET/PATCH /api/v1/users/me/smart-tasks.
///
/// When hidden, a list shows its colour instead: a `#` where there is room for one, a dot where
/// there is not, and list settings drops the image row — an image the app never draws is not
/// something to set up.
enum ListImagesVisibility {
    /// - Parameters:
    ///   - preference: `UserSettings.showListImages`. Nil follows the experiment; an explicit
    ///     choice always wins.
    ///   - hideFlag: whether hide_list_images is on for this user.
    nonisolated static func shouldShow(preference: Bool?, hideFlag: Bool) -> Bool {
        preference ?? !hideFlag
    }

    /// The settings update for the "Show list images" toggle: that field and nothing else, so
    /// merging it cannot write a default over another setting.
    nonisolated static func change(showListImages: Bool) -> UserSettings {
        var update = UserSettings(smartTaskCreationEnabled: nil, emailToTaskEnabled: nil,
                                  defaultTaskDueOffset: nil, defaultDueTime: nil,
                                  subtaskDisplay: nil, taskDisplayMode: nil)
        update.showListImages = showListImages
        return update
    }

    /// What a hidden list image draws instead.
    enum Placeholder: Equatable {
        /// The list's colour as a `#`, as web's sidebar draws it.
        case hash
        /// The list's colour as a dot — below 12pt a glyph is a smudge.
        case dot

        nonisolated static func forSize(_ size: CGFloat) -> Placeholder {
            size >= 12 ? .hash : .dot
        }
    }
}

/// The resolved answer, for views. Follows both inputs, so flipping the toggle on another
/// device or a flag change from the server redraws every list icon.
@MainActor
final class ListImagesVisibilityStore: ObservableObject {
    static let shared = ListImagesVisibilityStore()

    @Published private(set) var showListImages: Bool

    private var cancellable: AnyCancellable?

    private init() {
        let flags = FeatureFlagService.shared
        let settings = UserSettingsService.shared
        showListImages = ListImagesVisibility.shouldShow(
            preference: settings.settings.showListImages,
            hideFlag: flags.isEnabled(.hideListImages))
        cancellable = flags.$snapshot
            .combineLatest(settings.$settings)
            .map { snapshot, settings in
                ListImagesVisibility.shouldShow(preference: settings.showListImages,
                                                hideFlag: snapshot.isEnabled(.hideListImages))
            }
            .removeDuplicates()
            .sink { [weak self] in self?.showListImages = $0 }
    }

    /// Stores an explicit choice, which wins over the experiment from then on.
    func setShowListImages(_ value: Bool) {
        UserSettingsService.shared.updateSettings(ListImagesVisibility.change(showListImages: value))
    }
}
