import Foundation

enum TranscriptEvent: Sendable {
    /// Running transcript of the current utterance.
    case partial(String)
    /// Final transcript of the utterance; listening ends after this.
    case final(String)
    /// Normalized input level, 0...1.
    case level(Double)
    case unavailable(String)
}

/// Capture and playback. Cancelling the consuming task stops capture/playback.
protocol SpeechClient: Sendable {
    func listen() -> AsyncStream<TranscriptEvent>
    /// Speaks text; yields normalized output levels until playback ends.
    func speak(_ text: String) -> AsyncStream<Double>
}
