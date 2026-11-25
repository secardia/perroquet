import SwiftUI

/// "To review" page: pending dictations one at a time, to correct and validate or delete.
struct AnnotationView: View {
    @Environment(AnnotationStore.self) private var store
    @Environment(ValidatedStore.self) private var validated

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "To review")
            if let current = store.current {
                HStack(spacing: 0) {
                    RecordingList(
                        recordings: store.recordings,
                        selectedID: current.id,
                        rows: store.rows,
                        hasMore: store.hasMore,
                        onSelect: store.select,
                        onLoadMore: store.loadMore
                    )
                    .frame(width: 280)
                    RecordingEditor(
                        recording: current,
                        text: $draft,
                        shouldAutoplay: store.takeAutoplayRequest,
                        onDelete: store.delete,
                        onValidate: {
                            try store.save(draft)
                            Task { await validated.reload() }
                        })
                }
            } else {
                ContentUnavailableView("All reviewed", systemImage: "checkmark.circle")
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.background)
        .task { await store.reload() }
        .onChange(of: store.current?.id, initial: true) { draft = store.currentText }
    }
}
