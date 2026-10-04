import SwiftUI

/// Floating top bar over the feed: chats on the left, and on
/// the right one glass module holding new chat, this chat's outputs, and the
/// chat's menu. While finding in the chat, the find bar takes its place.
/// Place it in a safe-area-respecting overlay aligned `.top`; the bar's
/// controls sit below the safe top while its blur wash extends under it.
struct TopBar: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation

    @State private var confirmingDelete = false
    @State private var taps = 0

    /// The chrome row: 44pt, iOS's standard bar-button size, scaled by device.
    static let barHeight: CGFloat = Tokens.scaled(44)
    static let bottomPadding: CGFloat = pt(8)
    /// How far the blur wash fades out below the bar.
    private static let fadeOverhang: CGFloat = pt(28)

    var body: some View {
        Group {
            // Find in chat replaces the bar outright. It sits outside the
            // glass container so the bar's glass does not morph into it.
            if navigation.findOpen {
                // Grows out of the menu it was opened from, and back into it.
                FindBar()
                    .transition(.scale(scale: 0.25, anchor: .trailing).combined(with: .opacity))
            } else {
                GlassEffectContainer { bar }
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.36, bounce: 0.18), value: navigation.findOpen)
        .frame(height: Self.barHeight)
        .padding(.horizontal, pt(16))
        .padding(.bottom, Self.bottomPadding)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ProgressiveBlur(edge: .top)
                .padding(.bottom, -Self.fadeOverhang)
                .ignoresSafeArea(edges: .top)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .confirmationDialog("Delete this chat?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { chat.delete(chat.active.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var bar: some View {
        HStack(spacing: pt(10)) {
            GlassCircleButton(icon: .menuLeft, accessibilityLabel: "Chats") {
                navigation.toggleDrawer()
            }

            Spacer(minLength: 0)

            module
        }
    }

    /// New chat, outputs, and the chat's menu, in one piece of glass.
    ///
    /// The label owns the same native glass as the left control. Keep the
    /// system Menu itself plain so it does not add a second filled capsule.
    /// New chat and Outputs have independent transparent tap targets.
    private var module: some View {
        menu
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    moduleButton(label: "New chat") { chat.newChat() }
                    moduleButton(label: "Outputs") { navigation.present(.outputs) }
                        .accessibilityValue(
                            chat.outputCount == 0 ? Text("") : Text("\(chat.outputCount) in this chat")
                        )
                }
            }
    }

    /// The chat's menu: the system's, with its own glyphs.
    private var menu: some View {
        Menu {
            Button { chat.togglePin(chat.active.id) } label: {
                Label { Text(chat.active.isPinned ? "Unpin" : "Pin") } icon: { MenuIcon(icon: .pinTack) }
            }
            .disabled(chat.isEmpty)
            Button { navigation.present(.files) } label: {
                Label { Text("Uploaded files") } icon: { MenuIcon(icon: .folder) }
            }
            Button { navigation.findOpen = true } label: {
                Label { Text("Find in chat") } icon: { MenuIcon(icon: .search) }
            }
            .disabled(chat.isEmpty)
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label { Text("Delete") } icon: { MenuIcon(icon: .trash) }
            }
            .disabled(chat.isEmpty)
        } label: {
            HStack(spacing: 0) {
                moduleGlyph(.composePen)
                // Filled once the chat has outputs, outlined until then.
                moduleGlyph(.ballotCircle, filled: chat.outputCount > 0)
                moduleGlyph(.more)
            }
            .glassControl(in: Capsule(), interactive: true)
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("More"))
    }

    /// A clear tap target over one of the capsule's glyphs.
    private func moduleButton(label: String, action: @escaping () -> Void) -> some View {
        Button {
            taps += 1
            action()
        } label: {
            Color.clear
                .frame(width: Self.slot + pt(4), height: Self.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// One glyph's slot in the capsule.
    private static let slot: CGFloat = Tokens.scaled(44)

    private func moduleGlyph(_ icon: NucleoIcon, filled: Bool = false) -> some View {
        Icon(icon, size: 22, color: Tokens.foreground, filled: filled)
            .frame(width: Self.slot + pt(4), height: Self.barHeight)
    }
}

/// Find in chat: a field, how many replies and messages match, and steps to
/// move between them. Each step scrolls the feed to that message.
private struct FindBar: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var matches: [UUID] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return chat.messages.filter { $0.text.localizedCaseInsensitiveContains(needle) }.map(\.id)
    }

    var body: some View {
        // One piece of glass: search glyph, field, count, previous, next, close.
        HStack(spacing: 0) {
            Icon(.search, size: 18, color: Tokens.foregroundSecondary)
                .padding(.leading, pt(14))
                .padding(.trailing, pt(8))
            TextField("Find in chat", text: $query)
                .font(.text)
                .foregroundStyle(Tokens.foreground)
                .tint(Tokens.foreground)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { step(1) }
            if !query.isEmpty {
                Text(matches.isEmpty ? "None" : "\(index + 1) of \(matches.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.foregroundSecondary)
                    .padding(.horizontal, pt(6))
            }
            control(.chevronDown, label: "Previous match") { step(-1) }
                .rotationEffect(.degrees(180))
                .disabled(matches.count < 2)
            control(.chevronDown, label: "Next match") { step(1) }
                .disabled(matches.count < 2)
            control(.xmark, label: "Done") { navigation.findOpen = false }
                .padding(.trailing, pt(4))
        }
        .frame(height: TopBar.barHeight)
        .glassControl(in: Capsule())
        .onAppear { focused = true }
        .onDisappear { navigation.findQuery = "" }
        .onChange(of: query) {
            navigation.findQuery = query
            index = 0
            if let first = matches.first { navigation.scrollTarget = first }
        }
        .onChange(of: chat.active.id) { navigation.findOpen = false }
    }

    private func control(_ icon: NucleoIcon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 18, color: Tokens.foreground)
                .frame(width: Tokens.scaled(36), height: TopBar.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }

    private func step(_ by: Int) {
        guard !matches.isEmpty else { return }
        index = (index + by + matches.count) % matches.count
        navigation.scrollTarget = matches[index]
    }
}
