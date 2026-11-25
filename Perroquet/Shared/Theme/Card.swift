import SwiftUI

/// Small gray caption above a card.
struct SectionLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 4)
    }
}

/// Rounded card whose rows are separated by a thin line. Use `CardRow` for each row.
struct Card<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                SectionLabel(title)
            }
            VStack(spacing: 0) {
                Group(subviews: content()) { subviews in
                    ForEach(subviews.indices, id: \.self) { index in
                        if index > 0 {
                            AppColors.separator.frame(height: 1)
                        }
                        subviews[index]
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: ControlCorners.card, style: .continuous)
                    .fill(AppColors.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: ControlCorners.card, style: .continuous))
        }
    }
}

/// One card row: 9 x 12 pt padding, content on the leading edge.
struct CardRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 13))
            .foregroundStyle(AppColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }
}

#Preview("Card") {
    let section = "Section"
    return Card(LocalizedStringKey(section)) {
        CardRow {
            HStack {
                Text(verbatim: "First row")
                Spacer()
                Text(verbatim: "Value").foregroundStyle(AppColors.textSecondary)
            }
        }
        CardRow { Text(verbatim: "Second row") }
    }
    .frame(width: 360)
    .padding(16)
    .background(AppColors.background)
}
