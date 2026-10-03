import SwiftUI

struct MemoryDetailSheet: View {
    let memoryID: UUID
    @Environment(ChatSessionStore.self) private var chat
    @State private var editing = false
    @State private var draft = ""

    private var item: MemoryItem? { chat.memories.first { $0.id == memoryID } }

    var body: some View {
        SheetScaffold(title:"Saved memory") {
            if let item {
                VStack(alignment:.leading,spacing:pt(16)) {
                    Text(item.text).font(.text).textSelection(.enabled)
                    if !item.sourceQuote.isEmpty {
                        Text("You said").font(.caption).foregroundStyle(Tokens.foregroundSecondary)
                        Text(item.sourceQuote).font(.text).textSelection(.enabled)
                    }
                    Text(item.createdAt.formatted(date:.abbreviated,time:.shortened))
                        .font(.caption).foregroundStyle(Tokens.foregroundSecondary)
                    HStack {
                        Button("Edit") { draft = item.text; editing = true }.frame(minHeight: pt(44))
                        Spacer()
                        Button("Forget",role:.destructive) { chat.forgetMemory(item.id) }.frame(minHeight: pt(44))
                    }
                    .font(.text)
                }
                .padding(SheetMetrics.rowPadX)
                .background(Tokens.cardFill,in:.rect(cornerRadius:SheetMetrics.cardRadius))
            } else {
                SheetEmptyState(icon:.brain,title:"Memory forgotten",message:"This saved memory has been removed. Original chat messages remain in their conversation.")
            }
        }
        .alert("Edit memory",isPresented:$editing) {
            TextField("Memory",text:$draft,axis:.vertical)
            Button("Cancel",role:.cancel) {}
            Button("Save") { chat.updateMemory(memoryID,text:draft) }
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
