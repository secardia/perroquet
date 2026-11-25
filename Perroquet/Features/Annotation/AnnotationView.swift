import AppKit
import SwiftUI

/// "To review" page: pending dictations one at a time, to correct and validate or delete.
struct AnnotationView: View {
    @Environment(AnnotationStore.self) private var store

    @State private var draft = ""

    var body: some View {
        Group {
            if let current = store.current {
                RecordingEditor(
                    recording: current,
                    text: $draft,
                    shouldAutoplay: store.takeAutoplayRequest,
                    onDelete: store.delete,
                    onValidate: { try store.save(draft) })
            } else {
                ContentUnavailableView("All reviewed", systemImage: "checkmark.circle")
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                Text("\(store.pendingCount) to review").foregroundStyle(.secondary)
                Button(action: store.previous) {
                    Label("Newer", systemImage: "chevron.up")
                }
                .disabled(!store.hasPrevious)
                .help("Newer")
                Button(action: store.next) {
                    Label("Older", systemImage: "chevron.down")
                }
                .disabled(!store.hasNext)
                .help("Older")
            }
        }
        .task { await store.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await store.reload() }
        }
        .task(id: store.current?.id) { draft = store.currentText }
    }

    private var subtitle: String {
        guard let id = store.current?.id else { return "" }
        return RecordingID.date(from: id)?.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()) ?? id
    }
}
