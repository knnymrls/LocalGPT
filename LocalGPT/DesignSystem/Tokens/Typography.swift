import SwiftUI

/// The whole app's type, in one place. Two sizes and one emphasis:
///
/// - `text`: 16pt regular. Everything a person reads: messages, the composer,
///   sheet rows, buttons, values.
/// - `title`: 16pt medium. Names: the chat title, a sheet's title, a card's
///   heading, and the on-device label.
/// - `caption`: 13pt regular. Secondary lines under or beside `text`.
/// - `micro`: 11pt regular. Citation chips only.
/// - `heading`: 24pt semibold. The app's name in the drawer, and nothing else.
/// - `emphasis`: 16pt semibold. The drawer's "Chat" pill, and nothing else.
///
/// Semibold appears in exactly two places, both in the drawer (`heading`
/// and `emphasis`). Feature code uses these and never builds a
/// font from a raw size.
extension Font {
    /// Sizes are the iPhone 17 Pro baseline. They scale with `Tokens.uiScale`
    /// along with every control and icon, so a wider phone is the same design
    /// drawn larger, not the same type inside bigger buttons.
    private static func size(_ points: CGFloat) -> CGFloat { points * Tokens.uiScale }

    static let text = Font.system(size: size(16))
    static let title = Font.system(size: size(16), weight: .medium)
    static let caption = Font.system(size: size(13))
    static let micro = Font.system(size: size(11))
    static let heading = Font.system(size: size(24), weight: .semibold)
    static let emphasis = Font.system(size: size(16), weight: .semibold)
}

/// A layout length on the device scale. Every padding, gap, size, and corner
/// radius in the app goes through this (or `Tokens.scaled`), so a wider phone
/// is the iPhone 17 Pro design drawn larger, with type, icons, controls, and
/// spacing all growing by the same factor.
func pt(_ points: CGFloat) -> CGFloat { Tokens.scaled(points) }
