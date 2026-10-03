import SwiftUI
import UIKit

/// The conversation feed. Follows streaming tokens only while the reader is
/// at the bottom; otherwise offers a jump-to-latest glass circle.
struct ChatFeed: View {
    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation

    @State private var position = ScrollPosition(edge: .bottom)
    /// True while the feed should stay pinned to the newest content.
    @State private var follows = true
    @State private var userScrolling = false
    @State private var atBottom = true
    @State private var width: CGFloat = 0

    /// Changes whenever the feed's tail grows or changes state.
    private struct Tail: Equatable {
        var count: Int
        var lastLength: Int
        var lastSteps: Int
        var lastHasArtifact: Bool
        var lastStatus: Message.Status?
    }

    private var tail: Tail {
        let last = chat.messages.last
        return Tail(
            count: chat.messages.count,
            lastLength: last?.text.count ?? 0,
            lastSteps: last?.steps.count ?? 0,
            lastHasArtifact: last?.artifact != nil,
            lastStatus: last?.status
        )
    }

    var body: some View {
        let messages = chat.messages
        let highlight = navigation.findOpen ? navigation.findQuery : ""

        ZStack(alignment: .bottom) {
            // Jumps to a message go through the reader. The scroll position
            // only ever targets the bottom edge: tracking message identity
            // made the feed snap a message to the corner whenever a reply
            // changed height, such as when its work steps were expanded.
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let prev = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        Group {
                            switch message.role {
                            case .user:
                                UserBubble(
                                    message: message,
                                    joinsAbove: prev?.role == .user,
                                    joinsBelow: next?.role == .user,
                                    maxWidth: width > 0 ? (width - pt(32)) * 0.72 : .infinity,
                                    highlight: highlight
                                )
                            case .assistant:
                                AssistantRow(message: message, highlight: highlight)
                            }
                        }
                        .padding(.top, Self.spacing(above: message, prev: prev))
                    }
                }
                .padding(.horizontal, pt(16))
                .padding(.bottom, pt(8))
            }
            .scrollPosition($position)
            .scrollEdgeEffectHidden(true, for: .all)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                // When a scroll by hand settles, where it settled decides
                // whether the feed keeps following.
                if phase == .idle { follows = atBottom }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                // At the latest message when the visible area reaches the
                // content's end, give or take a line.
                geo.visibleRect.maxY >= geo.contentSize.height - 32
            } action: { _, atBottom in
                self.atBottom = atBottom
                if atBottom {
                    follows = true
                } else if userScrolling {
                    follows = false
                }
            }
            .onChange(of: tail) { old, new in
                // Sending always returns to the latest message.
                if new.count > old.count,
                   chat.messages.suffix(new.count - old.count).contains(where: { $0.role == .user }) {
                    follows = true
                }
                if follows { position.scrollTo(edge: .bottom) }
            }
            .onChange(of: chat.active.id) {
                follows = true
                position.scrollTo(edge: .bottom)
            }
            .onChange(of: navigation.scrollTarget) { _, target in
                // An output was picked: bring its message to the top.
                guard let target else { return }
                follows = false
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .center) }
                navigation.scrollTarget = nil
            }
            }

        }
        // The jump-to-latest button lives above the composer, in ChatScreen.
        .onChange(of: follows) { _, follows in navigation.feedAtLatest = follows }
        .onChange(of: navigation.jumpToLatest) {
            follows = true
            withAnimation(.easeInOut(duration: 0.3)) { position.scrollTo(edge: .bottom) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private static func spacing(above message: Message, prev: Message?) -> CGFloat {
        guard let prev else { return 8 }
        return prev.role == .user && message.role == .user ? pt(4) : pt(16)
    }
}

// MARK: - Rows

private struct UserBubble: View {
    let message: Message
    let joinsAbove: Bool
    let joinsBelow: Bool
    let maxWidth: CGFloat
    var highlight = ""

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(FindHighlight.mark(AttributedString(message.text), query: highlight))
                .font(.text)
                .foregroundStyle(Tokens.foreground)
                .padding(.horizontal, pt(14))
                .padding(.vertical, pt(9))
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: joinsBelow ? pt(8) : pt(20),
                        topTrailingRadius: joinsAbove ? pt(8) : pt(20),
                        style: .continuous
                    )
                    .fill(Tokens.userBubble)
                )
                .frame(maxWidth: maxWidth, alignment: .trailing)
        }
    }
}

private struct AssistantRow: View {
    @Environment(ChatSessionStore.self) private var chat
    let message: Message
    var highlight = ""

    @State private var retries = 0

    private var documents: [Attachment] {
        message.documentIDs.compactMap { chat.attachment($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: pt(12)) {
            WorkDisclosure(message: message)
            if !message.text.isEmpty {
                MarkdownText(text: message.text, highlight: highlight)
            }
            if message.status != .streaming, !documents.isEmpty {
                VStack(spacing: pt(8)) {
                    ForEach(documents) { ReplyDocumentRow(document: $0) }
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.impact(weight: .light), trigger: retries)
    }

    @ViewBuilder
    private var footer: some View {
        switch message.status {
        case .failed:
            HStack(spacing: pt(4)) {
                Text("Reply interrupted.")
                    .font(.caption)
                    .foregroundStyle(Tokens.foregroundSecondary)
                Button {
                    retries += 1
                    chat.retry()
                } label: {
                    Icon(.refresh, size: 18, color: Tokens.foregroundSecondary)
                        .frame(width: pt(32), height: pt(32))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Retry reply"))
            }
        case .complete, .stopped:
            if !message.text.isEmpty {
                ReplyActions(message: message)
                    .padding(.top, -pt(6))
            }
        case .streaming:
            EmptyView()
        }
    }
}
