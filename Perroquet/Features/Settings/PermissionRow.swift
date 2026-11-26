import SwiftUI

/// A permission row: title and detail on the left, status (and the grant button) on the right.
struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let action: () -> Void

    var body: some View {
        CardRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(AppColors.textPrimary)
                    Text(detail).font(.system(size: 12)).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                if granted {
                    Text("Granted").foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("Not granted").foregroundStyle(AppColors.textSecondary)
                    Button("Grant…", action: action).buttonStyle(.appPrimary)
                }
            }
        }
    }
}
