import SwiftUI

/// Dimensions shared by segmented controls.
enum SegmentedMetrics {
    /// Default size of a segment cell.
    static let cell = CGSize(width: 76, height: 26)
}

/// Rounded group holding segmented cells; outer radius = cell radius + inset.
struct SegmentedGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: ControlCorners.inset) {
            content()
        }
        .padding(ControlCorners.inset)
        .background(
            RoundedRectangle(cornerRadius: ControlCorners.outer, style: .continuous)
                .fill(AppColors.background)
        )
    }
}

/// One segment cell: gray fill and primary text when selected, secondary text otherwise; the hitbox equals the fill.
struct SegmentedCell<Label: View>: View {
    var size: CGSize = SegmentedMetrics.cell
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: size.width, height: size.height)
        }
        .buttonStyle(SegmentedCellStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Fill of a segment cell: gray when selected, card-colored while pressed, clear otherwise.
private struct SegmentedCellStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ControlCorners.inner, style: .continuous)
        configuration.label
            .background(shape.fill(fill(isPressed: configuration.isPressed)))
            .contentShape(shape)
    }

    private func fill(isPressed: Bool) -> Color {
        if isSelected { return AppColors.button }
        return isPressed ? AppColors.card : Color.clear
    }
}

#Preview("Segmented") {
    SegmentedGroup {
        SegmentedCell(isSelected: true, action: {}) { Text(verbatim: "Tap") }
        SegmentedCell(isSelected: false, action: {}) { Text(verbatim: "Hold") }
    }
    .padding(16)
    .background(AppColors.card)
}
