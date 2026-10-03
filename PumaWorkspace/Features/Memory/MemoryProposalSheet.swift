import SwiftUI

/// "Remember this?": the assistant's proposed memory, editable before saving.
struct MemoryProposalSheet: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var seeded = false
    @State private var saves = 0

    var body: some View {
        SheetScaffold(title: "Remember this?") {
            VStack(spacing: SheetMetrics.cardGap) {
                SheetCard {
                    VStack(alignment: .leading, spacing: pt(6)) {
                        TextField("Memory", text: $text, axis: .vertical)
                            .font(.text)
                            .foregroundStyle(Tokens.foreground)
                            .lineLimit(1...6)
                        if let origin = chat.pendingMemory?.origin {
                            Text(origin)
                                .font(.caption)
                                .foregroundStyle(Tokens.foregroundSecondary)
                        }
                    }
                    .padding(.horizontal, SheetMetrics.rowPadX)
                    .padding(.vertical, pt(14))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SheetRow {
                        Text("Scope")
                            .font(.text)
                            .foregroundStyle(Tokens.foreground)
                    } accessory: {
                        Text(chat.pendingMemory?.scope ?? "This workspace")
                            .font(.text)
                            .foregroundStyle(Tokens.foregroundSecondary)
                    }
                }

                VStack(spacing: pt(6)) {
                    Button(action: save) {
                        Text("Save")
                            .font(.text)
                            .foregroundStyle(Tokens.foregroundInverse)
                            .frame(maxWidth: .infinity)
                            .frame(height: pt(48))
                            .background(Tokens.foreground, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)

                    Button("Not now", action: notNow)
                        .font(.text)
                        .foregroundStyle(Tokens.foregroundSecondary)
                        .frame(height: pt(44))
                        .buttonStyle(.pressable)
                }
            }
        }
        .sensoryFeedback(.success, trigger: saves)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            text = chat.pendingMemory?.text ?? ""
        }
        // A drag-dismiss (or any close without Save) declines the proposal.
        .onDisappear {
            if chat.pendingMemory != nil { chat.dismissMemory() }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty else { return }
        saves += 1
        chat.saveMemory(text: trimmed)
        dismiss()
    }

    private func notNow() {
        chat.dismissMemory()
        dismiss()
    }
}
