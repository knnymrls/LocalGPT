import QuickLook
import SwiftUI

/// "Uploaded files": every file and photo added to the app. A row opens the
/// file in its own sheet.
struct UploadedFilesSheet: View {
    @Environment(ChatSessionStore.self) private var chat

    private var files: [Attachment] { chat.attachments.filter { $0.readiness != .removed } }

    var body: some View {
        SheetScaffold(title: "Uploaded files", contentAlignment: files.isEmpty ? .center : .top) {
            if files.isEmpty {
                SheetEmptyState(
                    icon: .folder,
                    title: "No files yet",
                    message: "Photos and files you add with the plus button will appear here."
                )
            } else {
                FileList(files: files)
            }
        }
    }
}

/// A card of file rows. Tapping one opens that file in a sheet of its own,
/// over the sheet that lists it.
struct FileList: View {
    let files: [Attachment]

    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation
    @State private var opened: Attachment?

    var body: some View {
        SheetCard {
            ForEach(files) { file in
                Button { opened = file } label: {
                    FileRowLabel(file: file)
                        .padding(.horizontal, SheetMetrics.rowPadX)
                        .frame(height: SheetMetrics.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SheetRowButtonStyle())
            }
        }
        .sheet(item: $opened) { file in
            FileSheet(id: file.id)
                .environment(chat)
                .environment(navigation)
        }
    }
}

/// One file by itself, in the system's viewer (Quick Look), which reads
/// PDFs, text, CSV, images, and documents. A file with no copy on disk shows
/// the text read from it.
struct FileSheet: View {
    @Environment(ChatSessionStore.self) private var chat
    let id: UUID

    var body: some View {
        let file = chat.attachment(id)
        if let url = file?.fileURL {
            QuickLookView(url: url)
                .ignoresSafeArea()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            SheetScaffold(title: file?.name ?? "File") {
                if let file {
                    FilePreview(file: file)
                } else {
                    SheetEmptyState(icon: .folder, title: "This file was removed")
                }
            }
        }
    }
}

/// The system document viewer for one file.
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        let dismiss = dismiss
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close, primaryAction: UIAction { _ in dismiss() }
        )
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// What was read from a file: its image, or its text.
private struct FilePreview: View {
    let file: Attachment

    var body: some View {
        VStack(alignment: .leading, spacing: pt(14)) {
            if let data = file.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: pt(16), style: .continuous))
            }
            if file.previewText.isEmpty {
                if file.thumbnail == nil {
                    Text("There is no preview for this file yet.")
                        .font(.text)
                        .foregroundStyle(Tokens.foregroundSecondary)
                }
            } else {
                Text(file.previewText)
                    .font(.text)
                    .lineSpacing(2)
                    .foregroundStyle(Tokens.foreground)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
