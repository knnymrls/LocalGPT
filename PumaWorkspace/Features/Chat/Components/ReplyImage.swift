import SwiftUI
import UIKit

/// Images are content in the conversation, not document receipts. Preserve
/// output aspect ratios; sent inputs use square thumbnails. Tap for the original.
struct ReplyImage: View {
    let document: Attachment
    let compact: Bool
    @Environment(NavigationState.self) private var navigation
    @State private var image: UIImage?
    @State private var loading = true

    init(document: Attachment, compact: Bool = false) {
        self.document = document
        self.compact = compact
        _image = State(initialValue: document.thumbnail.flatMap { UIImage(data: $0) })
    }

    var body: some View {
        Button {
            navigation.present(.file(document.id))
        } label: {
            Group {
                if let image {
                    Group {
                        if compact {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: pt(120), height: pt(120))
                                .clipped()
                        } else {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: pt(360))
                        }
                    }
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
            .frame(width: compact ? pt(120) : nil, height: compact ? pt(120) : nil)
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
