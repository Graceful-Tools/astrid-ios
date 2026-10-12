import SwiftUI

/// The sidebar's brand header: logo and wordmark left, search far right (AITD-494).
///
/// Web's sidebar opens with this row (AWTD-1180), and Jon asked for it "across interfaces", so
/// iPhone, iPad and Mac draw the one view rather than three that agree today. The colours are
/// the caller's because the two apps resolve their themes differently; everything about the
/// arrangement is here.
struct SidebarBrandHeader: View {
    static let logoSize: CGFloat = 24

    let primary: Color
    let muted: Color
    /// Search is what the main pane is showing, so the icon reads as current, as web's does.
    let isSearchActive: Bool
    let onSearch: () -> Void

    @ObservedObject private var serverCapabilities = ServerCapabilityService.shared

    var body: some View {
        HStack(spacing: 8) {
            Image("AstridCharacter")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.logoSize, height: Self.logoSize)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            Text(serverCapabilities.capabilities.brand.resolvedWordmark)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(isSearchActive ? primary : muted)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .macPointingHand()
            .help(NSLocalizedString("actions.search", comment: ""))
            #endif
            .accessibilityLabel(NSLocalizedString("actions.search", comment: ""))
            .accessibilityIdentifier("sidebar.headerSearch")
        }
    }
}
