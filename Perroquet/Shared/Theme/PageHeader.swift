import SwiftUI

/// Fixed page header: the page title.
struct PageHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }
}

#Preview("Page header") {
    let title = "Page"
    return PageHeader(title: LocalizedStringKey(title))
        .frame(width: 420)
        .background(AppColors.background)
}
