import SwiftUI

/// The in-progress utterance, floating above the composer in voice mode.
/// No "Listening…" label: the aura is the status.
struct FloatingTranscript: View {
    @Environment(VoiceSessionController.self) private var voice

    private var visible: Bool { voice.isActive && !voice.liveTranscript.isEmpty }

    var body: some View {
        ZStack {
            if visible {
                // Centred italic 17/22, head-truncated so the newest words stay visible.
                Text(voice.liveTranscript)
                    .font(.text.italic())
                    .lineSpacing(1.7)
                    .foregroundStyle(Tokens.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, pt(28))
        .animation(.easeOut(duration: 0.16), value: visible)
        .allowsHitTesting(false)
    }
}
