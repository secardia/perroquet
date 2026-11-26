import PerroquetCore
import SwiftUI

/// Column of recordings (newest first) with one selected: date and length, then one line of text.
struct RecordingList: View {
    let recordings: [DatasetRecording]
    let selectedID: String?
    let rows: RecordingRows
    let hasMore: Bool
    let onSelect: (String) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(recordings) { recording in
                    row(recording)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private func row(_ recording: DatasetRecording) -> some View {
        let isSelected = selectedID == recording.id
        return Button { onSelect(recording.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.title(of: recording.id))
                    Spacer(minLength: 8)
                    if let duration = rows.durations[recording.id] {
                        Text(verbatim: duration.clockText).monospacedDigit()
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
                Text(rows.texts[recording.id] ?? " ")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous)
                    .fill(isSelected ? AppColors.selection : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task { await rows.load(recording) }
        .onAppear {
            if hasMore, recording.id == recordings.last?.id { onLoadMore() }
        }
    }

    private static func title(of id: String) -> String {
        RecordingID.date(from: id)?.formatted(.dateTime.day().month(.abbreviated).hour().minute()) ?? id
    }
}
