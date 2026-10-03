import AVFoundation
import SwiftUI
import UIKit

/// A document the reply drew on, shown at the end of the reply: the type's
/// glyph in its colour, the name, and an arrow. Tapping opens the file.
struct ReplyDocumentRow: View {
    let document: Attachment

    @Environment(NavigationState.self) private var navigation

    var body: some View {
        Button {
            navigation.present(.file(document.id))
        } label: {
            FileRowLabel(file: document)
            .padding(.horizontal, pt(18))
            .frame(height: Tokens.scaled(48))
            .background(Tokens.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(Tokens.border, lineWidth: 0.75) }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("\(document.name), \(document.kind.displayName)"))
    }
}

/// The three things a reader can do with a finished reply: copy it, ask for
/// it again, or have it read aloud.
struct ReplyActions: View {
    let message: Message

    @Environment(ChatSessionStore.self) private var chat
    @Environment(NavigationState.self) private var navigation
    @State private var taps = 0
    @State private var copied = false
    private var reader: SpeechReader { .shared }

    var body: some View {
        HStack(spacing: pt(2)) {
            action(copied ? .done : .copy, label: "Copy reply") {
                UIPasteboard.general.string = message.text
                navigation.show(notice: "Message copied")
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    copied = false
                }
            }
            action(.refresh, label: "Retry reply") {
                chat.regenerate(message.id)
            }
            .disabled(chat.isStreaming)
            // Filled while this reply is the one being read.
            action(
                .speaker, filled: reader.speakingID == message.id,
                label: reader.speakingID == message.id ? "Stop reading" : "Read aloud"
            ) {
                reader.toggle(message.id, text: MarkdownText.plain(message.text))
            }
        }
        // The first glyph's edge lines up with the reply's text.
        .padding(.leading, -pt(7))
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private func action(
        _ icon: NucleoIcon, filled: Bool = false, label: String, perform: @escaping () -> Void
    ) -> some View {
        Button {
            taps += 1
            perform()
        } label: {
            Icon(icon, size: 18, color: filled ? Tokens.foreground : Tokens.foregroundMuted, filled: filled)
                .frame(width: pt(32), height: pt(32))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }
}

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
    @ObservationIgnored private var generation = 0
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
        generation += 1
        clock?.cancel()
        clock = nil
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
        isPaused = false
        elapsed = 0
    }

    private func speak(from start: Int) {
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        base = start
        offset = start
        isPaused = false
        let utterance = AVSpeechUtterance(string: (text as NSString).substring(from: start))
        // The system's scale runs 0...1 with 0.5 as normal speech.
        utterance.rate = Float(min(0.5 + (speed - 1) * 0.12, 0.65))
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let location = characterRange.location
        Task { @MainActor in self.offset = self.base + location }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let ended = self.generation
            // Only the utterance still in play ends the reading.
            if !self.synthesizer.isSpeaking, ended == self.generation { self.stop() }
        }
    }
}

/// The read-aloud player: play or pause, the time read so far, speed, a skip
/// back and forward, and close. It sits under the top bar while a reply is
/// being read.
struct ReadAloudBar: View {
    private var reader: SpeechReader { .shared }
    @State private var taps = 0

    var body: some View {
        HStack(spacing: pt(2)) {
            control(reader.isPaused ? .play : .pause, label: reader.isPaused ? "Play" : "Pause") {
                reader.togglePause()
            }
            Text(Self.time(reader.elapsed))
                .font(.title)
                .monospacedDigit()
                .foregroundStyle(Tokens.foreground)
            Spacer(minLength: pt(8))
            Button {
                taps += 1
                reader.cycleSpeed()
            } label: {
                Text(Self.speedLabel(reader.speed))
                    .font(.title)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.foreground)
                    .frame(minWidth: Tokens.scaled(44), minHeight: Tokens.scaled(40))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Speed \(Self.speedLabel(reader.speed))"))
            skip("gobackward.15", label: "Back 15 seconds") { reader.skip(-15) }
            skip("goforward.15", label: "Forward 15 seconds") { reader.skip(15) }
            control(.xmark, label: "Stop reading") { reader.stop() }
        }
        .padding(.horizontal, pt(8))
        .frame(height: Tokens.scaled(52))
        .glassControl(in: Capsule())
        .padding(.horizontal, pt(12))
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private func control(_ icon: NucleoIcon, label: String, action: @escaping () -> Void) -> some View {
        Button {
            taps += 1
            action()
        } label: {
            Icon(icon, size: 20, color: Tokens.foreground)
                .frame(width: Tokens.scaled(40), height: Tokens.scaled(40))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }

    /// The 15-second skips use the system's own symbols: Nucleo has no
    /// glyph that carries the "15".
    private func skip(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20 * Tokens.uiScale, weight: .regular))
                .foregroundStyle(Tokens.foreground)
                .frame(width: Tokens.scaled(40), height: Tokens.scaled(40))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }

    private static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func speedLabel(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))x" : "\(speed.formatted())x"
    }
}

/// A short confirmation under the top bar: a tick and a line of text in one
/// piece of glass.
struct NoticeBar: View {
    let text: String

    var body: some View {
        HStack(spacing: pt(10)) {
            Icon(.done, size: 12, color: Tokens.foregroundInverse)
                .frame(width: pt(22), height: pt(22))
                .background(Tokens.foreground, in: Circle())
            Text(text)
                .font(.title)
                .foregroundStyle(Tokens.foreground)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pt(16))
        .frame(height: Tokens.scaled(52))
        .glassControl(in: Capsule())
        .padding(.horizontal, pt(12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
