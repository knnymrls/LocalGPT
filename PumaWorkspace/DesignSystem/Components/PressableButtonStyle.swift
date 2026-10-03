import SwiftUI

/// Slashy's press response for icon buttons: scale 0.92 and opacity 0.9 while
/// held, settling back on a spring.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.92
    var pressedOpacity: Double = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
