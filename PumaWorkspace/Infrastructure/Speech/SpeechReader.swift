@preconcurrency import AVFoundation
import Foundation
import Observation

/// Reads one reply aloud with the system voice. On-device, like the rest.
/// It keeps its place in the text, so it can pause, skip, and change speed.
@MainActor
@Observable
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechReader()
    static let speeds: [Double] = [1, 1.25, 1.5, 2]

    /// The reply being read, if any.
    private(set) var speakingID: UUID?
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var speed: Double = 1

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var text = ""
    /// Where the current utterance began in `text`, and how far it has read.
    @ObservationIgnored private var base = 0
    @ObservationIgnored private var offset = 0
    /// Marks the current utterance, so a replaced one ending is ignored.
    @ObservationIgnored private var utterance: AVSpeechUtterance?
    @ObservationIgnored private var clock: Task<Void, Never>?

    /// About how many characters the voice reads in a second at 1x.
    private static let charactersPerSecond = 15.0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ id: UUID, text: String) {
        if speakingID == id {
            stop()
            return
        }
        stop()
        guard !text.isEmpty else { return }
        self.text = text
        speakingID = id
        elapsed = 0
        speak(from: 0)
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.speakingID != nil else { return }
                if !self.isPaused { self.elapsed += 0.25 }
            }
        }
    }

    func togglePause() {
        guard speakingID != nil else { return }
        if isPaused {
            synthesizer.continueSpeaking()
        } else {
            synthesizer.pauseSpeaking(at: .immediate)
        }
        isPaused.toggle()
    }

    /// Moves by about this many seconds of reading, forward or back.
    func skip(_ seconds: Double) {
        guard speakingID != nil else { return }
        let length = (text as NSString).length
        let target = offset + Int(seconds * Self.charactersPerSecond * speed)
        guard target < length else {
            stop()
            return
        }
        elapsed = max(0, elapsed + seconds)
        speak(from: max(0, target))
    }

    func cycleSpeed() {
        let index = Self.speeds.firstIndex(of: speed) ?? 0
        speed = Self.speeds[(index + 1) % Self.speeds.count]
        if speakingID != nil { speak(from: offset) }
    }

    func stop() {
        utterance = nil
        clock?.cancel()
        clock = nil
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
        isPaused = false
        elapsed = 0
        LocalAudioSession.shared.releaseAudioIfIdle()
    }

    private func speak(from start: Int) {
        utterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        base = start
        offset = start
        isPaused = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: (text as NSString).substring(from: start))
        // The system's scale runs 0...1 with 0.5 as normal speech.
        utterance.rate = Float(min(0.5 + (speed - 1) * 0.12, 0.65))
        self.utterance = utterance
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let location = characterRange.location
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.utterance, ObjectIdentifier(current) == identity else { return }
            self.offset = self.base + location
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.utterance, ObjectIdentifier(current) == identity else { return }
            self.stop()
        }
    }
}
