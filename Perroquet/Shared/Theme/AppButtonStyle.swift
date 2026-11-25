import SwiftUI

/// Filled, borderless, rounded button. `neutral` is gray, `primary` is parrot green on dark green.
struct AppButtonStyle: ButtonStyle {
    /// Color scheme of the button.
    enum Variant {
        /// Gray fill.
        case neutral
        /// Parrot green on dark green.
        case primary
    }

    /// Color scheme of the button.
    let variant: Variant

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous)
                    .fill(fill(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous))
    }

    private var foreground: Color {
        switch variant {
        case .neutral: AppColors.text
        case .primary: AppColors.accent
        }
    }

    private func fill(isPressed: Bool) -> Color {
        switch variant {
        case .neutral: isPressed ? AppColors.buttonPressed : AppColors.button
        case .primary: isPressed ? AppColors.accentMutedPressed : AppColors.accentMuted
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    /// Gray filled button.
    static var appNeutral: AppButtonStyle { AppButtonStyle(variant: .neutral) }
    /// Parrot green primary action button.
    static var appPrimary: AppButtonStyle { AppButtonStyle(variant: .primary) }
}

#Preview("Buttons") {
    HStack(spacing: 8) {
        Button {} label: { Text(verbatim: "Neutral") }.buttonStyle(.appNeutral)
        Button {} label: { Text(verbatim: "Primary") }.buttonStyle(.appPrimary)
        Button {} label: { Text(verbatim: "Disabled") }.buttonStyle(.appPrimary).disabled(true)
    }
    .padding(16)
    .background(AppColors.background)
}
