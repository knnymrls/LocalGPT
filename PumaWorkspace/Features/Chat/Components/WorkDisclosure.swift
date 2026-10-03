import SwiftUI

/// What the assistant did before it answered, after Slashy's
/// `ToolActivityGroup.tsx`. While it works, each step appears as it happens
/// and the current one shimmers. Once the answer starts, the steps fold into
/// one quiet "Worked for 3s" row that expands on tap.
struct WorkDisclosure: View {
    let message: Message

    @State private var expanded = false
    @State private var taps = 0

    /// Working means the reply is live and has not started writing yet.
    private var isWorking: Bool { message.status == .streaming && message.text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWorking {
                if message.steps.isEmpty {
                    ShimmerText(text: "Thinking", base: Tokens.foregroundMuted, sheen: Tokens.foreground)
                } else {
                    ForEach(Array(message.steps.enumerated()), id: \.offset) { index, step in
                        row(step, live: index == message.steps.count - 1)
                            .padding(.top, index == 0 ? -pt(6) : 0)
                            .transition(.opacity)
                    }
                }
            } else if !message.steps.isEmpty {
                header
                if expanded {
                    ForEach(Array(message.steps.enumerated()), id: \.offset) { _, step in
                        row(step, live: false)
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: message.steps.count)
        .animation(.easeOut(duration: 0.22), value: expanded)
        .animation(.easeOut(duration: 0.22), value: isWorking)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private var label: String {
        guard let seconds = message.workSeconds, seconds > 0 else { return "Worked" }
        return seconds < 60 ? "Worked for \(seconds)s" : "Worked for \(seconds / 60)m \(seconds % 60)s"
    }

    private var header: some View {
        Button {
            taps += 1
            expanded.toggle()
        } label: {
            HStack(spacing: pt(4)) {
                Text(label)
                    .font(.text)
                    .foregroundStyle(Tokens.foregroundSecondary)
                Icon(.chevronRight, size: 15, color: Tokens.foregroundMuted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(expanded ? "Collapses work steps" : "Expands work steps"))
    }

    /// A step is a line of text in the reply's own size, with no glyph.
    private func row(_ text: String, live: Bool) -> some View {
        Group {
            if live {
                ShimmerText(text: text, base: Tokens.foregroundMuted, sheen: Tokens.foreground)
            } else {
                Text(text)
                    .font(.text)
                    .foregroundStyle(Tokens.foregroundMuted)
                    .lineLimit(2)
            }
        }
        .padding(.top, pt(6))
    }
}

/// One quiet highlight travelling across a line of text. Motion shows the
/// work is live without dots. After Slashy's `ActivityShimmerText.tsx`.
struct ShimmerText: View {
    let text: String
    let base: Color
    let sheen: Color

    @State private var width: CGFloat = 0
    @State private var sweeping = false
    private static let band: CGFloat = 80

    var body: some View {
        label
            .foregroundStyle(base)
            .overlay {
                // The band travels inside a layer the size of the label, and
                // the label masks that whole layer.
                Color.clear
                    .overlay {
                        LinearGradient(colors: [.clear, sheen, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.band)
                            .offset(x: sweeping ? width / 2 + Self.band : -width / 2 - Self.band)
                    }
                    .mask { label.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: false)) { sweeping = true }
            }
    }

    private var label: some View {
        Text(text)
            .font(.text)
            .lineLimit(2)
    }
}
