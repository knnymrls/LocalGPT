import SwiftUI
import UIKit

/// Images are content in the conversation, not document receipts. Preserve
/// their aspect ratio and open the original when tapped.
struct ReplyImage: View {
    let document: Attachment
    @Environment(NavigationState.self) private var navigation
    @State private var image: UIImage?
    @State private var loading = true

    init(document: Attachment) {
        self.document = document
        _image = State(initialValue: document.thumbnail.flatMap { UIImage(data: $0) })
    }

    var body: some View {
        Button {
            navigation.present(.file(document.id))
        } label: {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: pt(16), style: .continuous))
                } else if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: pt(120))
                } else {
                    Text("Image preview unavailable. Tap to open.")
                        .font(.caption)
                        .foregroundStyle(Tokens.foregroundSecondary)
                        .frame(maxWidth: .infinity, minHeight: pt(80))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(document.name))
        .accessibilityHint("Opens the full-size image")
        .task(id: document) {
            loading = true
            if let url = document.fileURL,
               let data = await ImagePreviewCache.shared.preview(url: url, fingerprint: document.fingerprint),
               !Task.isCancelled {
                image = UIImage(data: data)
            }
            if !Task.isCancelled { loading = false }
        }
    }
}
