#if DEBUG
import Foundation

/// Opens a specific UI state for review screenshots: `-uiState <name>`.
/// Names: empty, drawer, history, streaming, stopped, failed, comparison, revised,
/// sources, outputs, voice, voiceReply, micUnavailable, evidence,
/// evidenceMissing, memory, liveCompare, liveVoice.
@MainActor
enum DebugLaunchState {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiState"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func apply(chat: ChatSessionStore, voice: VoiceSessionController, navigation: NavigationState) {
        guard let state = requested else { return }
        let model = Fixtures.defaultModelID
        let sources: Set<UUID> = [Fixtures.harborID, Fixtures.riversideID, Fixtures.guestUpdateID]
        let compareTurn = [
            Message(role: .user, text: "Compare the two venues"),
            Message(role: .assistant, text: Fixtures.comparisonReply, modelID: model, artifact: Fixtures.comparison),
        ]
        let revisedTurn = [
            Message(role: .user, text: "The guest count is now 140, all seated"),
            Message(role: .assistant, text: Fixtures.revisedReply, modelID: model, artifact: Fixtures.revisedComparison),
        ]

        switch state {
        case "drawer":
            navigation.drawerOpen = true
        case "history":
            if let first = chat.history.first { chat.select(first.id) }
        case "streaming":
            chat.debugSeed(messages: [
                Message(role: .user, text: "Summarize the screenshot update"),
                Message(role: .assistant, text: "Maya confirmed a final count of 140 guests, all seated, and two guests who use", modelID: model, status: .streaming),
            ], selected: sources, title: "Screenshot update")
        case "stopped":
            chat.debugSeed(messages: [
                Message(role: .user, text: "Summarize the screenshot update"),
                Message(role: .assistant, text: "Maya confirmed a final count of 140 guests, all seated, and", modelID: model, status: .stopped),
            ], selected: sources, title: "Screenshot update")
        case "failed":
            chat.debugSeed(messages: [
                Message(role: .user, text: "Compare the venues, then fail"),
                Message(role: .assistant, text: "", modelID: model, status: .failed),
            ], title: "Venue check")
        case "find":
            chat.debugSeed(messages: compareTurn + revisedTurn, selected: sources, title: "Venue comparison")
            navigation.findOpen = true
        case "comparison":
            chat.debugSeed(messages: compareTurn, selected: sources, title: "Venue comparison")
        case "revised":
            chat.debugSeed(messages: compareTurn + revisedTurn, selected: sources, title: "Venue comparison")
            chat.notes = "Ask Riverside about a ramp."
        case "sources":
            chat.debugSeed(messages: [], selected: [Fixtures.harborID, Fixtures.riversideID])
        case "outputs":
            chat.debugSeed(messages: compareTurn + revisedTurn, selected: sources, title: "Venue comparison")
            navigation.present(.outputs)
        case "voice":
            voice.debugShowListening(transcript: "Compare the two venues for capacity, price, and", energy: 0.8)
        case "voiceReply":
            chat.debugSeed(messages: compareTurn, selected: sources, title: "Venue comparison")
            voice.debugShowSpeaking(energy: 0.8)
        case "micUnavailable":
            voice.start()
        case "evidence":
            chat.debugSeed(messages: compareTurn, selected: sources, title: "Venue comparison")
            if let c = Fixtures.comparison.cells["accessibility"]?["harbor"]?.citations.first {
                navigation.present(.evidence(c))
            }
        case "evidenceMissing":
            navigation.present(.evidence(Fixtures.missingCitation))
        case "memory":
            chat.debugSeed(messages: compareTurn + revisedTurn, selected: sources, title: "Venue comparison")
            chat.debugProposeMemory(Fixtures.memoryProposal)
        case "liveCompare":
            // Exercises the real mock send/stream path (no seeding).
            chat.toggleSource(Fixtures.harborID)
            chat.toggleSource(Fixtures.riversideID)
            chat.draft = "Compare the two venues"
            chat.send()
        case "liveVoice":
            // Exercises the mock speech path end to end.
            voice.start()
        default:
            break
        }
    }
}
#endif
