import SwiftUI

/// A superscript source number. Tapping opens the cited passage.
struct CitationChip: View {
    let citation: Citation

    @Environment(NavigationState.self) private var navigation
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            navigation.present(.evidence(citation))
        } label: {
            Text("\(citation.number)")
                .font(.micro)
                .monospacedDigit()
                .foregroundStyle(Tokens.foregroundSecondary)
                .padding(.horizontal, pt(5))
                .frame(minWidth: pt(16), minHeight: pt(16))
                .background(Tokens.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Tokens.border, lineWidth: 0.5))
                .padding(pt(4))
                .contentShape(Rectangle())
                .padding(-pt(4))
        }
        .buttonStyle(.pressable)
        // Ride above the neighbouring value's baseline, superscript-style.
        .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] + 5 }
        .alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + 5 }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel("Source \(citation.number)")
    }
}
