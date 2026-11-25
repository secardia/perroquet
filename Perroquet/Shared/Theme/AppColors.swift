import SwiftUI

/// The app palette: the only source of colors for views.
enum AppColors {
    /// Window background.
    static let background = Color(hex: 0x1C1C1F)
    /// Card and panel fill.
    static let card = Color(hex: 0x26262A)
    /// Thin dividers.
    static let separator = Color(hex: 0x303034)
    /// Selected row fill.
    static let selection = Color(hex: 0x2E2E31)
    /// Neutral button fill.
    static let button = Color(hex: 0x353538)
    /// Neutral button fill while pressed.
    static let buttonPressed = Color(hex: 0x404044)

    /// Primary text.
    static let textPrimary = Color(hex: 0xD6D6D6)
    /// Body text.
    static let text = Color(hex: 0xBDBDBD)
    /// Secondary text.
    static let textSecondary = Color(hex: 0x8A8A8A)
    /// Tertiary text and inactive icons.
    static let textTertiary = Color(hex: 0x6E6E6E)

    /// The parrot red-orange, reserved for the selected page icon, active toggles, play and played waveform, primary actions and the ready or listening pill.
    static let accent = Color(hex: 0xF07548)
    /// Dark red-orange fill behind accent content.
    static let accentMuted = Color(hex: 0x3D2219)
    /// Dark red-orange fill while pressed.
    static let accentMutedPressed = Color(hex: 0x4A2A1E)

    /// Error messages; muted red readable on the background, never used as a fill.
    static let error = Color(hex: 0xE5746E)
}

/// Corner radii: nested controls follow outer = inner + inset.
enum ControlCorners {
    /// Card radius.
    static let card: CGFloat = 10
    /// Button radius.
    static let button: CGFloat = 8
    /// Gap between a nested control and its container.
    static let inset: CGFloat = 2
    /// Radius of a control nested in a group.
    static let inner: CGFloat = button
    /// Radius of the group around nested controls.
    static let outer: CGFloat = inner + inset
}

extension Color {
    /// A color from a 24-bit `0xRRGGBB` value.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview("Palette") {
    let swatches: [(String, Color)] = [
        ("background", AppColors.background), ("card", AppColors.card),
        ("separator", AppColors.separator), ("selection", AppColors.selection),
        ("button", AppColors.button), ("accent", AppColors.accent),
        ("accentMuted", AppColors.accentMuted),
    ]
    return HStack(spacing: 8) {
        ForEach(swatches, id: \.0) { swatch in
            RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous)
                .fill(swatch.1)
                .frame(width: 48, height: 48)
        }
    }
    .padding(16)
    .background(AppColors.background)
}
