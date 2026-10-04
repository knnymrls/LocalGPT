import SwiftUI

/// The end of a conversation, shown as the long-press preview in the drawer.
/// Self-contained: a context menu preview is rendered outside the app's view
/// tree, so it takes plain values and reads no environment objects.
struct ChatPreview: View {
    let messages: [Message]

    private var tail: [Message] { Array(messages.suffix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: pt(14)) {
            ForEach(tail) { message in
                switch message.role {
                case .user:
                    Text(message.text)
                        .font(.text)
                        .foregroundStyle(Tokens.foreground)
                        .padding(.horizontal, pt(14))
                        .padding(.vertical, pt(9))
                        .background(Tokens.userBubble, in: RoundedRectangle(cornerRadius: pt(20), style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, pt(48))
                case .assistant:
                    VStack(alignment: .leading, spacing: pt(8)) {
                        if !message.text.isEmpty {
                            Text(message.text)
                                .font(.text)
                                .foregroundStyle(Tokens.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let comparison = message.artifact {
                            HStack(spacing: pt(10)) {
                                Icon(.draft, size: 18, color: Tokens.foreground)
                                Text(comparison.title)
                                    .font(.text)
                                    .foregroundStyle(Tokens.foreground)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, pt(14))
                            .frame(height: pt(44))
                            .background(Tokens.cardFill, in: RoundedRectangle(cornerRadius: pt(14), style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(pt(18))
        .frame(width: pt(340))
        // As tall as its messages, up to a cap. Past the cap it stays
        // bottom-aligned, so the newest messages show and older ones run off
        // the top, like the conversation itself.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: pt(380), alignment: .bottom)
        .clipped()
        .background(Tokens.background)
    }
}
