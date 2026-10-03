import SwiftUI

/// "Outputs": the files this chat's replies worked from, and the things it
/// was asked to remember. A file opens in its own sheet.
struct OutputsSheet: View {
    @Environment(ChatSessionStore.self) private var chat

    var body: some View {
        SheetScaffold(title: "Outputs") {
            if chat.outputs.isEmpty && chat.memories.isEmpty {
                SheetEmptyState(
                    icon: .ballotCircle,
                    title: "No outputs yet",
                    message: "Files from this chat's replies and anything you ask it to remember will appear here."
                )
            } else {
                VStack(spacing: SheetMetrics.cardGap) {
                    if !chat.outputs.isEmpty {
                        FileList(files: chat.outputs)
                    }
                    if !chat.memories.isEmpty {
                        VStack(spacing: 0) {
                            SheetSectionLabel(title: "Remembered")
                            MemoryList()
                        }
                    }
                }
            }
        }
    }
}
