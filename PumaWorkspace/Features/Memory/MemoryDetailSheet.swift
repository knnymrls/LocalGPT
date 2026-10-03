import SwiftUI

struct MemoryDetailSheet: View {
    let memoryID: UUID
    @Environment(ChatSessionStore.self) private var chat

    private var item: MemoryItem? { chat.memories.first { $0.id == memoryID } }

    var body: some View {
        SheetScaffold(title:"Saved memory") {
            if let item {
                SheetCard {
                    Text(item.text)
                        .font(.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SheetMetrics.rowPadX)
                        .padding(.vertical, pt(14))
                }
            } else {
                SheetEmptyState(icon:.brain,title:"Memory removed",message:"This memory is no longer saved.")
            }
        }
    }
}

struct SavedMemoryReceipt: View {
    let ids: [UUID]
    @Environment(NavigationState.self) private var navigation
    var body: some View {
        VStack(alignment:.leading,spacing:pt(6)) {
            ForEach(ids,id:\.self) { id in
                Button { navigation.present(.savedMemory(id)) } label: {
                    HStack(spacing:pt(6)) {
                        Icon(.brain,size:14,color:Tokens.foregroundSecondary)
                        Text("Saved to memory").font(.caption)
                    }
                    .foregroundStyle(Tokens.foregroundSecondary)
                    .frame(minHeight:pt(32),alignment:.leading)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Saved to memory. View saved memory")
            }
        }
    }
}
