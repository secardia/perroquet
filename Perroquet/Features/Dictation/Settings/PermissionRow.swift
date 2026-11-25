import SwiftUI

/// A permission row styled like a two-line `LabeledContent`, but with the status centered on both lines
/// (`LabeledContent` aligns its value with the title only).
struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Text("Not granted").foregroundStyle(.secondary)
                Button("Grant…", action: action)
            }
        }
    }
}
