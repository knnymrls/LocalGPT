import Foundation

enum TranscriptEvent: Sendable {
    case preparing(String)
    case ready
    /// Running transcript of the current utterance.
    case partial(String)
    /// Final transcript of the utterance; listening ends after this.
    case final(String)
    /// Normalized input level, 0...1.
    case level(Double)
    case unavailable(String)
}

enum PlaybackEvent: Sendable {
    case level(Double)
    case finished
    case failed(String)
}

/// Capture and playback. Cancelling the consuming task stops capture/playback.
protocol SpeechClient: Sendable {
    /// Own the audio session across all turns, including time spent thinking or quietly listening.
    func beginConversation(id: UUID) async
    func endConversation(id: UUID) async
    func listen() -> AsyncStream<TranscriptEvent>
    /// Speaks text; distinguishes successful completion from interrupted or unavailable audio.
    func speak(_ text: String) -> AsyncStream<PlaybackEvent>
}

extension SpeechClient {
    func beginConversation(id: UUID) async {}
    func endConversation(id: UUID) async {}
}
