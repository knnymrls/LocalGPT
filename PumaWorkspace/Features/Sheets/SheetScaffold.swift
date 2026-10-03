import SwiftUI

// Sheets are native: a NavigationStack with an inline title, the system
// toolbar (its buttons get Liquid Glass for free), standard detents, and the
// system sheet material and corner radius. Only the grouped cards inside keep
// Slashy's metrics.

enum SheetMetrics {
    static let rowHeight: CGFloat = Tokens.scaled(54)
    static let cardRadius: CGFloat = pt(20)
    static let cardGap: CGFloat = pt(18)
    static let padX: CGFloat = pt(20)
    /// Row inset, also the divider inset.
    static let rowPadX: CGFloat = pt(16)
    static let hairline: CGFloat = 0.5
}

/// A sheet's root: owns the navigation stack and detents.
struct SheetScaffold<Content: View>: View {
    let title: String
    var detents: Set<PresentationDetent>
    var contentAlignment: Alignment
    @ViewBuilder var content: Content

    init(
        title: String,
        detents: Set<PresentationDetent> = [.medium, .large],
        contentAlignment: Alignment = .top,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detents = detents
        self.contentAlignment = contentAlignment
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            SheetPage(title: title, isRoot: true, contentAlignment: contentAlignment) { content }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }
}

/// One page inside a sheet's navigation stack. Its header is the app's own:
/// the same 44pt glass circle and Nucleo glyph as the top bar (an X on the
/// root page, a chevron on pushed pages) and the title in the app's type. The
/// system navigation bar is hidden so the two never differ.
struct SheetPage<Content: View>: View {
    let title: String
    var isRoot = false
    var contentAlignment: Alignment
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    init(title: String, isRoot: Bool = false, contentAlignment: Alignment = .top, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isRoot = isRoot
        self.contentAlignment = contentAlignment
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { viewport in
                ScrollView {
                    content
                        .padding(.horizontal, SheetMetrics.padX)
                        .padding(.bottom, contentAlignment == .center ? 0 : pt(24))
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: contentAlignment)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(.title)
                .foregroundStyle(Tokens.foreground)
                .lineLimit(1)
                .padding(.horizontal, pt(60))
                .accessibilityAddTraits(.isHeader)
            HStack {
                // On the root page `dismiss` closes the sheet; on a pushed page it pops.
                GlassCircleButton(
                    icon: isRoot ? .xmark : .chevronLeft,
                    accessibilityLabel: isRoot ? "Close" : "Back"
                ) {
                    dismiss()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, SheetMetrics.padX)
        .padding(.top, pt(16))
        .padding(.bottom, pt(14))
    }
}

/// A grouped card. Hairlines (inset 16) are drawn between its direct subviews.
struct SheetCard<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id {
                        SheetDivider()
                    }
                    subview
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Tokens.cardFill, in: .rect(cornerRadius: SheetMetrics.cardRadius, style: .continuous))
        .clipShape(.rect(cornerRadius: SheetMetrics.cardRadius, style: .continuous))
    }
}

/// The 0.5pt rule between card rows, starting at the row's text inset.
struct SheetDivider: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.border)
            .frame(height: SheetMetrics.hairline)
            .padding(.leading, SheetMetrics.rowPadX)
    }
}

/// A card's label: secondary text, sentence case.
struct SheetSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.text)
            .foregroundStyle(Tokens.foregroundSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SheetMetrics.rowPadX)
            .padding(.bottom, pt(8))
    }
}

/// One card row: 54pt tall, 16pt inset, press wash drawn inside the row.
///
/// The trailing accessory sits above the row's own tap target, so a control
/// there (a selection check, a retry button) takes its own taps.
struct SheetRow<Content: View, Accessory: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    init(
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.action = action
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let action {
                Button(action: action) { rowLabel }
                    .buttonStyle(SheetRowButtonStyle())
            } else {
                rowLabel
            }
            accessory
                .padding(.trailing, SheetMetrics.rowPadX)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: pt(12)) {
            content
            Spacer(minLength: 0)
            // Reserve the accessory's column so text never runs under it.
            accessory.hidden().accessibilityHidden(true)
        }
        .padding(.horizontal, SheetMetrics.rowPadX)
        .padding(.vertical, pt(8))
        .frame(minHeight: SheetMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

extension SheetRow where Accessory == EmptyView {
    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(action: action, content: content, accessory: { EmptyView() })
    }
}

/// NAV_SHEET_PRESS_*: a translucent wash while the finger is down.
struct SheetRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Tokens.pressWash.opacity(configuration.isPressed ? 1 : 0))
            .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.2), value: configuration.isPressed)
    }
}

/// Centred empty state: a 44pt glyph, a line, and an optional action.
struct SheetEmptyState<Action: View>: View {
    let icon: NucleoIcon
    let title: String
    var message: String?
    @ViewBuilder var action: Action

    init(icon: NucleoIcon, title: String, message: String? = nil, @ViewBuilder action: () -> Action) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(spacing: pt(10)) {
            Icon(icon, size: 44, color: Tokens.foregroundMuted)
                .padding(.bottom, pt(4))
            Text(title)
                .font(.text)
                .foregroundStyle(Tokens.foreground)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Tokens.foregroundSecondary)
                    .multilineTextAlignment(.center)
            }
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, pt(24))
    }
}

extension SheetEmptyState where Action == EmptyView {
    init(icon: NucleoIcon, title: String, message: String? = nil) {
        self.init(icon: icon, title: title, message: message, action: { EmptyView() })
    }
}
