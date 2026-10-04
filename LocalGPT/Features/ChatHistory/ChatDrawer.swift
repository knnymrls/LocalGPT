import SwiftUI

/// The drawer back layer: the app's name and a search button at the top, the chats
/// in the middle, and a "Chat" pill at the bottom left that starts a new one.
struct ChatDrawer: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation

    @State private var tapCount = 0
    @State private var renaming: Conversation?
    @State private var renameText = ""

    /// The text axis: rows are inset 14 with 10 of padding inside.
    private static let textX: CGFloat = pt(24)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Pinned chats get their own labelled section; the label
                    // for the rest only appears once there is a pinned one.
                    let pinned = chat.history.filter(\.isPinned)
                    let others = chat.history.filter { !$0.isPinned }
                    if !pinned.isEmpty {
                        sectionLabel("Pinned")
                        ForEach(pinned) { historyRow($0) }
                        if !others.isEmpty {
                            sectionLabel("Chats")
                                .padding(.top, pt(14))
                        }
                    }
                    ForEach(others) { historyRow($0) }
                    if chat.history.isEmpty {
                        Text("No chats yet")
                            .font(.text)
                            .foregroundStyle(Tokens.foregroundSecondary)
                            .padding(.horizontal, Self.textX)
                            .frame(height: Tokens.scaled(44))
                    }
                }
                .padding(.top, pt(8))
                .padding(.bottom, pt(12))
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(Tokens.drawerBackground.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .alert("Rename chat", isPresented: renameBinding, presenting: renaming) { conversation in
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            // The default action, so the system draws it as the prominent blue button.
            Button("Save") { chat.rename(conversation.id, to: renameText) }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// A section's label: medium weight, secondary ink, like the sheets' labels.
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.title)
            .foregroundStyle(Tokens.foregroundSecondary)
            .padding(.horizontal, Self.textX)
            .frame(height: Tokens.scaled(36))
            .accessibilityAddTraits(.isHeader)
    }

    /// "LocalGPT" and the search button, which opens the search page.
    private var header: some View {
        HStack(spacing: pt(10)) {
            Text("LocalGPT")
                .font(.heading)
                .foregroundStyle(Tokens.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            GlassCircleButton(icon: .search, accessibilityLabel: "Search chats") {
                navigation.openSearch()
            }
        }
        // The same row as the chat surface's top bar: same top edge and
        // height, so "LocalGPT", search, and the menu button share one centre line.
        .frame(height: TopBar.barHeight)
        .padding(.leading, Self.textX)
        .padding(.trailing, pt(16))
        .padding(.bottom, TopBar.bottomPadding)
    }

    /// The new-chat pill, bottom left.
    private var footer: some View {
        HStack {
            Button {
                select { chat.newChat() }
            } label: {
                HStack(spacing: pt(8)) {
                    Icon(.composePen, size: 20, color: Tokens.foregroundInverse)
                    Text("Chat")
                        .font(.emphasis)
                        .foregroundStyle(Tokens.foregroundInverse)
                }
                .padding(.horizontal, pt(18))
                .frame(height: Tokens.scaled(48))
                .background(Tokens.foreground, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("New chat"))
            Spacer(minLength: 0)
            // In the same column as the search button above it.
            GlassCircleButton(icon: .brain, accessibilityLabel: "Memories") {
                navigation.present(.memories)
            }
        }
        .padding(.leading, pt(20))
        .padding(.trailing, pt(16))
        .padding(.top, pt(8))
        // Same 8pt above the safe area as the composer card, so their bottom
        // edges line up.
        .padding(.bottom, pt(8))
    }

    /// A chat row. Tap opens the chat; touch and hold lifts a preview of the
    /// conversation with Pin, Rename, and Delete beneath it.
    private func historyRow(_ conversation: Conversation) -> some View {
        let active = conversation.id == chat.activeID
        let label = conversation.title ?? "New chat"
        let shape = RoundedRectangle(cornerRadius: pt(10), style: .continuous)
        return Button {
            select { chat.select(conversation.id) }
        } label: {
            HStack(spacing: pt(8)) {
                Text(label)
                    .font(.text)
                    .foregroundStyle(Tokens.foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, pt(10))
            .frame(height: Tokens.scaled(44))
            .background(active ? Tokens.hover : .clear, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                chat.togglePin(conversation.id)
            } label: {
                Label { Text(conversation.isPinned ? "Unpin" : "Pin") } icon: { MenuIcon(icon: .pinTack) }
            }
            Button {
                renameText = conversation.title ?? ""
                renaming = conversation
            } label: {
                Label { Text("Rename") } icon: { MenuIcon(icon: .pen) }
            }
            Button(role: .destructive) {
                chat.delete(conversation.id)
            } label: {
                Label { Text("Delete") } icon: { MenuIcon(icon: .trash) }
            }
        } preview: {
            ChatPreview(messages: conversation.messages)
        }
        .padding(.horizontal, pt(14))
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    /// Light haptic, close the drawer, then perform the destination action.
    private func select(_ action: () -> Void) {
        tapCount += 1
        navigation.closeDrawer()
        action()
    }
}
