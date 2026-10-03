import SwiftUI

/// Empty-chat prompt suggestions, sitting directly above the composer.
/// Tapping one fills the draft; it never sends.
struct SuggestionList: View {
    @Environment(ChatSessionStore.self) private var chat
    @State private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: pt(8)) {
            ForEach(ConversationStarter.examples) { item in
                Button {
                    taps += 1
                    chat.applySuggestion(item.prompt)
                } label: {
                    HStack(spacing: pt(12)) {
                        Icon(item.icon, size: 20)
                        VStack(alignment: .leading, spacing: pt(3)) {
                            Text(item.title)
                                .font(.text)
                                .foregroundStyle(Tokens.foreground)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(Tokens.foregroundMuted)
                        }
                        .multilineTextAlignment(.leading)
                    }
                    .padding(.leading, pt(14))
                    .padding(.trailing, pt(8))
                    .padding(.vertical, pt(8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(item.title))
                .accessibilityHint(Text("\(item.detail). Adds an editable example to the message field."))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
