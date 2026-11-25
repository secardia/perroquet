import AppKit
import SwiftUI

/// "Validated" page: the validated dictations as a list, with the selected one open for correction.
struct ValidatedListView: View {
    @Environment(ValidatedStore.self) private var store

    @State private var draft = ""

    var body: some View {
        Group {
            if store.recordings.isEmpty {
                ContentUnavailableView("No validated dictations", systemImage: "tray")
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: 280)
                    Divider()
                    detail
                }
            }
        }
        .task { await store.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await store.reload() }
        }
        .task(id: store.selectedID) { draft = store.currentText }
    }

    private var list: some View {
        List(
            store.recordings,
            selection: Binding(get: { store.selectedID }, set: { store.select($0) })
        ) { recording in
            row(recording)
        }
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

    private func row(_ recording: DatasetRecording) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.title(of: recording.id)).font(.headline)
            Text(store.texts[recording.id] ?? " ")
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .tag(recording.id)
        .task { await store.loadText(for: recording) }
    }

    private static func title(of id: String) -> String {
        RecordingID.date(from: id)?.formatted(.dateTime.day().month(.abbreviated).hour().minute()) ?? id
    }
}
