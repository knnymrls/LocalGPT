#if DEBUG
import Foundation

/// Simulated transcription and playback with a synthetic speech envelope.
struct MockSpeechClient: SpeechClient {
    var utterance = "Compare the two venues for capacity, price, and accessibility"
    var unavailable = false

    func listen() -> AsyncStream<TranscriptEvent> {
        let words = utterance.split(separator: " ").map(String.init)
        let unavailable = unavailable
        return AsyncStream { continuation in
            let task = Task {
                if unavailable {
                    continuation.yield(.unavailable("Microphone unavailable"))
                    continuation.finish()
                    return
                }
                // Lead-in silence.
                for _ in 0..<12 {
                    continuation.yield(.level(0.04))
                    try? await Task.sleep(for: .milliseconds(50))
                }
                var spoken: [String] = []
                for (index, word) in words.enumerated() {
                    if Task.isCancelled { break }
                    // ~330 ms per word: syllable bumps on a speech envelope.
                    for step in 0..<6 {
                        let phase = Double(step) / 6
                        let syllable = sin(phase * .pi)
                        let jitter = 0.12 * sin(Double(index * 7 + step) * 1.3)
                        continuation.yield(.level(min(1, max(0, 0.35 + 0.55 * syllable + jitter))))
                        try? await Task.sleep(for: .milliseconds(55))
                    }
                    spoken.append(word)
                    continuation.yield(.partial(spoken.joined(separator: " ")))
                }
                if !Task.isCancelled {
                    for _ in 0..<10 {
                        continuation.yield(.level(0.03))
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    continuation.yield(.final(spoken.joined(separator: " ")))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func speak(_ text: String) -> AsyncStream<Double> {
        let wordCount = max(1, text.split(separator: " ").count)
        return AsyncStream { continuation in
            let task = Task {
                for index in 0..<(wordCount * 5) {
                    if Task.isCancelled { break }
                    let phase = Double(index % 5) / 5
                    continuation.yield(0.3 + 0.6 * sin(phase * .pi) + 0.08 * sin(Double(index) * 0.7))
                    try? await Task.sleep(for: .milliseconds(60))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
