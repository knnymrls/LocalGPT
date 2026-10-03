import SwiftUI

extension View {
    /// The workspace's one sheet presentation, bound to
    /// `NavigationState.activeSheet`. Also raises "Remember this?" when the
    /// assistant proposes a memory and nothing else is showing.
    func workspaceSheets() -> some View {
        modifier(WorkspaceSheetsModifier())
    }
}

private struct WorkspaceSheetsModifier: ViewModifier {
    @Environment(NavigationState.self) private var navigation
    @Environment(ChatSessionStore.self) private var chat
    @Environment(VoiceSessionController.self) private var voice

    func body(content: Content) -> some View {
        @Bindable var navigation = navigation

        content
            .sheet(item: $navigation.activeSheet, onDismiss: presentPendingMemory) { sheet in
                sheetContent(sheet)
                    .environment(chat)
                    .environment(voice)
                    .environment(navigation)
            }
            .onChange(of: chat.pendingMemory) { _, pending in
                guard pending != nil else { return }
                presentPendingMemory()
            }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: NavigationState.Sheet) -> some View {
        switch sheet {
        case .outputs: OutputsSheet()
        case .memories: MemoriesSheet()
        case .files: UploadedFilesSheet()
        case .file(let id): FileSheet(id: id)
        case .evidence(let citation): EvidenceSheet(citation: citation)
        case .memoryProposal: MemoryProposalSheet()
        case .savedMemory(let id): MemoryDetailSheet(memoryID:id)
        }
    }

    /// A proposal that arrived while another sheet was up waits for it to close.
    private func presentPendingMemory() {
        guard chat.pendingMemory != nil, navigation.activeSheet == nil else { return }
        navigation.present(.memoryProposal)
    }
}
