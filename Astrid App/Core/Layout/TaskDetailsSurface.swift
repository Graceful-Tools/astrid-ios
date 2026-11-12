//  TaskDetailsSurface.swift
//  The task details face, per theme: one definition shared by the details view, the iPad panel
//  card behind it, and the arrow on the panel's leading edge (AITD-627). The arrow used to be
//  filled with the panel's base colour while the details view painted its own face on top, so in
//  Ocean (cyan washed with white) the arrow read as a dark cyan wedge beside a near-white card.
//  Built into iOS and the Mac.

import SwiftUI

struct TaskDetailsSurface: View, Equatable {
    /// The theme's base background.
    let base: Color
    /// How much white is laid over `base` — Ocean's wash, nothing elsewhere.
    let whiteWash: Double

    /// `theme` should already be resolved (`ThemeMode.resolved(for:)`); an unresolved Auto reads
    /// as Light.
    init(theme: ThemeMode) {
        switch theme {
        case .ocean:
            base = Theme.Ocean.bgPrimary
            whiteWash = 0.8
        case .dark:
            base = Theme.Dark.bgPrimary
            whiteWash = 0
        case .light, .auto:
            base = Theme.bgPrimary
            whiteWash = 0
        }
    }

    var body: some View {
        ZStack {
            base
            if whiteWash > 0 {
                Color.white.opacity(whiteWash)
            }
        }
    }
}
