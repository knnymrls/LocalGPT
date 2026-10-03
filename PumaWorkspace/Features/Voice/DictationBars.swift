import SwiftUI

/// The dictation waveform: a row of capsules scrolling right to left, each one
/// a recent sample of the input level.
struct DictationBars: View {
    @Environment(VoiceSessionController.self) private var voice
    @State private var samples: [Double] = Array(repeating: 0, count: 80)

    private static let barWidth: CGFloat = pt(3)
    private static let gap: CGFloat = pt(3)

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, Int((proxy.size.width + Self.gap) / (Self.barWidth + Self.gap)))
            HStack(alignment: .center, spacing: Self.gap) {
                ForEach(Array(samples.suffix(count).enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(Tokens.foreground.opacity(0.3 + 0.7 * sample))
                        .frame(width: Self.barWidth, height: pt(4) + pt(20) * sample)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .animation(.linear(duration: 0.07), value: samples)
        }
        .task {
            while !Task.isCancelled {
                samples.removeFirst()
                samples.append(min(1, max(0, voice.energy)))
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
        .accessibilityLabel(Text("Dictating"))
    }
}
