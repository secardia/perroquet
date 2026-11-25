import SwiftUI

/// Page layout: a title (with an optional accessory beside it) above scrolling content, on the window background.
struct PageScaffold<Accessory: View, Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    accessory()
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(AppColors.background)
    }
}

extension PageScaffold where Accessory == EmptyView {
    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

#Preview("Page") {
    let title = "Page"
    return PageScaffold(title: LocalizedStringKey(title)) {
        Card {
            CardRow { Text(verbatim: "Row") }
        }
    }
    .frame(width: 420, height: 200)
}
