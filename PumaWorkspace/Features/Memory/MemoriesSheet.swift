import SwiftUI

/// "Memories": everything the assistant was asked to remember, opened from
/// the drawer.
struct MemoriesSheet: View {
    @Environment(ChatSessionStore.self) private var chat

    var body: some View {
        SheetScaffold(title: "Memories") {
            if chat.memories.isEmpty {
                SheetEmptyState(
                    icon: .brain,
                    title: "No memories yet",
                    message: chat.memoryFailure ?? "Context you share is remembered automatically. Saved memories can be reviewed, edited, or forgotten here."
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

/// A card of remembered things, one plain line each. Press and hold a row to
/// edit or forget it.
struct MemoryList: View {
    var items: [MemoryItem]? = nil
    @Environment(NavigationState.self) private var navigation
    @Environment(ChatSessionStore.self) private var chat
    @State private var editing: MemoryItem?
    @State private var editText = ""

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
                        Button("Edit") {
                            editText = memory.text
                            editing = memory
                        }
                        Button("Forget", role: .destructive) {
                            chat.forgetMemory(memory.id)
                        }
                    }
            }
        }
        .alert("Edit memory", isPresented: isEditing, presenting: editing) { memory in
            TextField("Memory", text: $editText, axis: .vertical)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { chat.updateMemory(memory.id, text: text) }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var isEditing: Binding<Bool> {
        Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
    }
}
