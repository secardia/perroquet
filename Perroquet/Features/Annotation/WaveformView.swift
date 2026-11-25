import SwiftUI

/// Bars of a waveform with the played part in the accent color; click or drag to seek.
struct WaveformView: View {
    /// Peaks in 0…1; nil while computing.
    let peaks: [Float]?
    /// Playback position in 0…1.
    let progress: Double
    /// Called with the fraction (0…1) chosen when a click or drag ends.
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    private static let barWidth: CGFloat = 2
    private static let minimumBarHeight: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let values = peaks ?? [Float](repeating: 0, count: Waveform.bucketCount)
                let slot = size.width / CGFloat(values.count)
                let shown = dragFraction ?? progress
                for (index, value) in values.enumerated() {
                    let height = max(Self.minimumBarHeight, CGFloat(value) * size.height)
                    let x = slot * CGFloat(index) + (slot - Self.barWidth) / 2
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: Self.barWidth, height: height)
                    let played = (Double(index) + 0.5) / Double(values.count) <= shown
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: Self.barWidth / 2),
                        with: .style(played ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = fraction(at: $0.location.x, width: geometry.size.width) }
                    .onEnded {
                        let chosen = fraction(at: $0.location.x, width: geometry.size.width)
                        dragFraction = nil
                        onSeek(chosen)
                    })
        }
        .frame(height: 36)
    }

    private func fraction(at x: CGFloat, width: CGFloat) -> Double {
        width > 0 ? Double(min(max(x / width, 0), 1)) : 0
    }
}
