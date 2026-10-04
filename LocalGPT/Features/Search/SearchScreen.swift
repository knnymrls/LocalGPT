import SwiftUI

/// Full-screen search over chats. An empty prompt in the middle, results as
/// you type, and the field docked at the bottom above the keyboard with a
/// close button beside it.
struct SearchScreen: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation

    @State private var query = ""
    @State private var taps = 0
    @FocusState private var focused: Bool

    private static let barHeight: CGFloat = Tokens.scaled(48)

    private struct Hit: Identifiable {
        let conversation: Conversation
        /// The matching message line, when the match was not in the title.
        let snippet: String?
        var id: UUID { conversation.id }
    }

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hits: [Hit] {
        guard !needle.isEmpty else { return [] }
        return chat.history.compactMap { conversation in
            if (conversation.title ?? "").localizedCaseInsensitiveContains(needle) {
                return Hit(conversation: conversation, snippet: conversation.messages.last?.text)
            }
            if let message = conversation.messages.first(where: { $0.text.localizedCaseInsensitiveContains(needle) }) {
                return Hit(conversation: conversation, snippet: message.text)
            }
            return nil
        }
    }

    var body: some View {
        ZStack {
            Tokens.background.ignoresSafeArea()

            if needle.isEmpty {
                prompt(icon: .search, text: "Search chats")
            } else if hits.isEmpty {
                prompt(icon: .search, text: "No chats found")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(hits) { hit in
                            row(hit)
                        }
                    }
                    .padding(.top, pt(8))
                    .padding(.bottom, pt(12))
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .onAppear { focused = true }
    }

    private func prompt(icon: NucleoIcon, text: String) -> some View {
        VStack(spacing: pt(16)) {
            Icon(icon, size: 28, color: Tokens.foregroundSecondary)
            Text(text)
                .font(.text)
                .foregroundStyle(Tokens.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(_ hit: Hit) -> some View {
        Button {
            taps += 1
            chat.select(hit.conversation.id)
            navigation.closeSearch()
            navigation.closeDrawer()
        } label: {
            VStack(alignment: .leading, spacing: pt(2)) {
                Text(hit.conversation.title ?? "New chat")
                    .font(.text)
                    .foregroundStyle(Tokens.foreground)
                    .lineLimit(1)
                if let snippet = hit.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(Tokens.foregroundSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, pt(24))
            .padding(.vertical, pt(10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// The docked field and close button. Rides the keyboard.
    private var bar: some View {
        GlassEffectContainer(spacing: pt(10)) {
            HStack(spacing: pt(10)) {
                HStack(spacing: pt(10)) {
                    Icon(.search, size: 20, color: Tokens.foreground)
                    TextField(
                        "",
                        text: $query,
                        prompt: Text("Search").foregroundStyle(Tokens.foregroundSecondary)
                    )
                    .font(.text)
                    .foregroundStyle(Tokens.foreground)
                    .tint(Tokens.foreground)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text("Search"))
                }
                .padding(.horizontal, pt(16))
                .frame(height: Self.barHeight)
                .glassControl(in: Capsule())

                GlassCircleButton(
                    icon: .xmark,
                    size: Self.barHeight,
                    accessibilityLabel: "Close search"
                ) {
                    focused = false
                    navigation.closeSearch()
                }
            }
        }
        .padding(.horizontal, pt(16))
        .padding(.top, pt(8))
        .padding(.bottom, pt(8))
    }
}
