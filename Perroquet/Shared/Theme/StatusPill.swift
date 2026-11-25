import SwiftUI

/// Small state pill: gray while loading, parrot green when the app is ready or listening.
struct StatusPill: View {
    /// Color scheme of the pill.
    enum Tone {
        /// Gray: nothing happening or still loading.
        case neutral
        /// Parrot green: ready or listening.
        case active
    }

    let label: Text
    let tone: Tone

    init(_ title: LocalizedStringKey, tone: Tone) {
        label = Text(title)
        self.tone = tone
    }

    init(verbatim title: String, tone: Tone) {
        label = Text(verbatim: title)
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            label
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
    }

    private var dotColor: Color {
        tone == .active ? AppColors.accent : AppColors.textTertiary
    }

    private var textColor: Color {
        tone == .active ? AppColors.accent : AppColors.textSecondary
    }

    private var background: Color {
        tone == .active ? AppColors.accentMuted : AppColors.button
    }
}

#Preview("Status pill") {
    HStack(spacing: 8) {
        StatusPill(verbatim: "Idle", tone: .neutral)
        StatusPill(verbatim: "Active", tone: .active)
    }
    .padding(16)
    .background(AppColors.background)
}
