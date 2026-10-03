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
                    message: "Things you ask it to remember will appear here."
                )
            } else {
                MemoryList()
            }
        }
    }
}

/// A card of remembered things, one plain line each. Press and hold a row to
/// edit or forget it.
struct MemoryList: View {
    @Environment(ChatSessionStore.self) private var chat
    @State private var editing: MemoryItem?
    @State private var editText = ""

    var body: some View {
        SheetCard {
            ForEach(chat.memories) { memory in
                Text(memory.text)
                    .font(.text)
                    .foregroundStyle(Tokens.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SheetMetrics.rowPadX)
                    .padding(.vertical, pt(14))
                    .frame(minHeight: SheetMetrics.rowHeight)
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
