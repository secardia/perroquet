import PerroquetCore
import SwiftUI

/// "Validated" page: the validated dictations as a list, with the selected one open for correction.
struct ValidatedListView: View {
    @Environment(ValidatedStore.self) private var store

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Validated")
            if store.recordings.isEmpty {
                ContentUnavailableView("No validated dictations", systemImage: "tray")
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    RecordingList(
                        recordings: store.recordings,
                        selectedID: store.selectedID,
                        rows: store.rows,
                        hasMore: store.hasMore,
                        onSelect: store.select,
                        onLoadMore: store.loadMore
                    )
                    .frame(width: 280)
                    detail
                }
            }
        }
        .background(AppColors.background)
        .task { await store.reload() }
        .onChange(of: store.selectedID, initial: true) { draft = store.currentText }
    }

    @ViewBuilder
    private var detail: some View {
        if let current = store.current {
            RecordingEditor(
                recording: current,
                text: $draft,
                shouldAutoplay: store.takeAutoplayRequest,
                onDelete: store.delete,
                onValidate: { try store.save(draft) })
        } else {
            Color.clear
        }
    }
}
