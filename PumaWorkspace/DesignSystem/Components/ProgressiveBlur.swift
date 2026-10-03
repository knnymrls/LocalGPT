import SwiftUI

/// Slashy's ProgressiveBlur for a screen edge: a blur that is full strength at
/// the edge and fades to nothing toward the content, with a wash of the page
/// colour so text under the status bar or home indicator stays quiet.
///
/// Place it behind a bar and let it run past the safe area. It must sit
/// outside any `GlassEffectContainer`, which renders its content offscreen.
struct ProgressiveBlur: View {
    enum Edge { case top, bottom }

    let edge: Edge

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            // Strong page-colour wash: the material alone reads as a gray band
            // on an empty page.
            Tokens.background.opacity(0.82)
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.5),
                    .init(color: .black.opacity(0.72), location: 0.68),
                    .init(color: .black.opacity(0.28), location: 0.86),
                    .init(color: .clear, location: 1),
                ],
                startPoint: edge == .top ? .top : .bottom,
                endPoint: edge == .top ? .bottom : .top
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
