import SwiftUI

/// Lasting context and explicit memories, opened from the drawer.
struct MemoriesSheet: View {
    @Environment(ChatSessionStore.self) private var chat

    var body: some View {
        SheetScaffold(title: "Memories") {
            if chat.memories.isEmpty {
                SheetEmptyState(
                    icon: .brain,
                    title: "No memories yet",
                    message: chat.memoryFailure ?? "Lasting preferences and things you ask to remember appear here."
                )
            } else {
                if let failure = chat.memoryFailure {
                    Text(failure).font(.footnote).foregroundStyle(.secondary)
                }
                MemoryList()
            }
        }
    }
}

/// One plain row per memory. Removal stays in the long-press menu.
struct MemoryList: View {
    var items: [MemoryItem]? = nil
    @Environment(NavigationState.self) private var navigation
    @Environment(ChatSessionStore.self) private var chat

    var body: some View {
        SheetCard {
            ForEach(items ?? chat.memories) { memory in
                Text(memory.text)
                    .font(.text)
                    .foregroundStyle(Tokens.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SheetMetrics.rowPadX)
                    .padding(.vertical, pt(14))
                    .frame(minHeight: SheetMetrics.rowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { navigation.present(.savedMemory(memory.id)) }
                    .accessibilityAddTraits(.isButton)
                    .contentShape(.contextMenuPreview, .rect(cornerRadius: SheetMetrics.cardRadius, style: .continuous))
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            chat.forgetMemory(memory.id)
                        }
                    }
            }
        }
    }
}
