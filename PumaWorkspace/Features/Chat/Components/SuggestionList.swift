import SwiftUI

/// Empty-chat prompt suggestions, sitting directly above the composer.
/// Tapping one fills the draft; it never sends.
struct SuggestionList: View {
    @Environment(ChatSessionStore.self) private var chat
    @State private var taps = 0

    private static let items: [(icon: NucleoIcon, text: String)] = [
        (.ai, "Compare the two venues"),
        (.search, "What's missing from the proposals"),
        (.images, "Summarize the screenshot update"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: pt(8)) {
            ForEach(Self.items, id: \.text) { item in
                Button {
                    taps += 1
                    chat.applySuggestion(item.text)
                } label: {
                    HStack(spacing: pt(8)) {
                        Icon(item.icon, size: 20)
                        Text(item.text)
                            .font(.text)
                            .foregroundStyle(Tokens.foreground)
                    }
                    .padding(.leading, pt(14))
                    .padding(.trailing, pt(8))
                    .padding(.vertical, pt(8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(item.text))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
