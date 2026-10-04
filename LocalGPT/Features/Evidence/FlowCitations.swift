import SwiftUI

struct FlowCitations: View {
    let citations:[Citation]
    @Environment(NavigationState.self) private var navigation
    var body: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:pt(8)) {
                ForEach(citations) { citation in
                    Button { navigation.present(.evidence(citation)) } label: {
                        Text("[\(citation.number)] \(citation.locator)")
                            .font(.caption).foregroundStyle(Tokens.foregroundSecondary)
                            .padding(.horizontal,pt(10)).frame(minHeight:pt(36))
                            .background(Tokens.surface,in:Capsule())
                    }.buttonStyle(.pressable)
                }
            }
        }
    }
}
