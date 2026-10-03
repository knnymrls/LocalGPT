import SwiftUI

// MARK: - Glass
//
// Native iOS 26 Liquid Glass for the material and the press response. On a
// flat white page the system's own edge all but vanishes, so `glassControl`
// adds the shared directional rim. Every glass surface uses it, with an
// optional control tint.

enum GlassMaterial {
    /// Only the sheet background fades; foreground text and controls stay opaque.
    static let sheetOpacity = 0.55
    static let sheetCornerRadius: CGFloat = pt(40)

    /// The shared control tint, for the rare surface that wants a wash.
    static let controlTint = Color(uiColor: Tokens.Material.glassTint)

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

/// A directional rim: a conic gradient masked to a 0.75pt ring. Colours run from
/// the top clockwise. The light comes from the top-left, so the two catches of
/// light sit at the top-left (where it enters) and bottom-right (where it
/// exits), and the two flanks at the top-right and bottom-left define the
/// shape. Light mode is a restrained graphite contour; dark mode is a quiet
/// white highlight with the same geometry. The centre stays fully transparent.
private struct GlassRim<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.colorScheme) private var colorScheme

    private var stops: [Gradient.Stop] {
        let turn: [CGFloat] = [0, 0.125, 0.375, 0.625, 0.875, 1]
        let graphite = Color(red: 44 / 255, green: 44 / 255, blue: 43 / 255)
        let alphas: [Double] = colorScheme == .dark
            ? [0.04, 0.015, 0.085, 0.015, 0.10, 0.04]
            : [0.10, 0.20, 0.05, 0.20, 0.04, 0.10]
        let ink: Color = colorScheme == .dark ? .white : graphite
        return zip(turn, alphas).map { Gradient.Stop(color: ink.opacity($1), location: $0) }
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                shape
                    .strokeBorder(
                        // 0 is straight up; SwiftUI's angular gradient starts at
                        // three o'clock, so turn it back a quarter.
                        AngularGradient(
                            stops: stops,
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            }
    }
}

/// Shared chrome recipe: clearer native glass, no drawn shadow, and the
/// directional rim. Every glass surface in the app goes through this, so they
/// cannot drift apart.
private struct GlassControl<S: InsettableShape>: ViewModifier {
    let shape: S
    let glass: Glass

    func body(content: Content) -> some View {
        content
            .modifier(GlassRim(shape: shape))
            .glassEffect(glass, in: shape)
    }
}

extension View {
    /// Rim, native glass, and lift, in `shape`. Use this for every glass
    /// surface; do not call `glassEffect` directly.
    func glassControl<S: InsettableShape>(in shape: S, glass: Glass = .clear) -> some View {
        modifier(GlassControl(shape: shape, glass: glass))
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
        .glassControl(in: Circle(), glass: .clear.interactive())
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .accessibilityLabel(Text(accessibilityLabel ?? icon.rawValue))
    }
}
