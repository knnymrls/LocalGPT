import SwiftUI

// MARK: - Glass
//
// Native system glass owns the material, edge, tint, and accessibility adaptation.

enum GlassMaterial {
    static let sheetCornerRadius: CGFloat = pt(40)

    /// Animate glass from this floor, never from 0: a glass view whose ancestors
    /// are at a true zero when it attaches never configures its backdrop.
    static let idleOpacity = Tokens.Glass.idleOpacity
}

extension AnyTransition {
    @MainActor static var glass: AnyTransition {
        .modifier(
            active: GlassFadeModifier(opacity: GlassMaterial.idleOpacity),
            identity: GlassFadeModifier(opacity: 1)
        )
    }
}

extension AnyTransition {
    @MainActor static func glass(scale: CGFloat, anchor: UnitPoint) -> AnyTransition {
        .glass.combined(with: .scale(scale: scale, anchor: anchor))
    }
}

private struct GlassFadeModifier: ViewModifier {
    let opacity: Double
    func body(content: Content) -> some View { content.opacity(opacity) }
}

extension View {
    /// Keep the base system material. Only interaction behavior is customized;
    /// appearance stays under the user's system Liquid Glass preference.
    @ViewBuilder
    func glassControl<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if interactive {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            glassEffect(in: shape)
        }
    }
}

/// A round glass chrome button carrying one Nucleo glyph: the top bar's menu
/// and attachments buttons, sheet close buttons, jump-to-latest. Native
/// interactive glass at an exact size; the system plays the press response.
struct GlassCircleButton: View {
    let icon: NucleoIcon
    var size: CGFloat
    var iconSize: CGFloat
    var iconColor: Color
    var accessibilityLabel: String?
    /// A small accent dot at the top right, drawn inside the glass.
    var badge = false
    let action: () -> Void

    @State private var tapCount = 0

    init(
        icon: NucleoIcon,
        size: CGFloat = Tokens.scaled(44),
        iconSize: CGFloat = 22,
        iconColor: Color = Tokens.foreground,
        accessibilityLabel: String? = nil,
        badge: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.iconSize = iconSize
        self.iconColor = iconColor
        self.accessibilityLabel = accessibilityLabel
        self.badge = badge
        self.action = action
    }

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Icon(icon, size: iconSize, color: iconColor)
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(Tokens.foreground)
                            .frame(width: pt(8), height: pt(8))
                            // On the circle's rim at the top right, inside the glass.
                            .padding(size * 0.12)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassControl(in: Circle(), interactive: true)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .accessibilityLabel(Text(accessibilityLabel ?? icon.rawValue))
    }
}
