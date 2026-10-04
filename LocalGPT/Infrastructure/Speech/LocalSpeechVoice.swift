import AVFoundation
import Foundation

/// One local voice policy for conversation playback and Read Aloud.
/// Re-enumerate at playback time so newly downloaded voices are picked up.
enum LocalSpeechVoice {
    static func preferred(language: String = AVSpeechSynthesisVoice.currentLanguageCode()) -> AVSpeechSynthesisVoice? {
        let tag = language.replacingOccurrences(of: "_", with: "-")
        let fallback = AVSpeechSynthesisVoice(language: tag)
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.caseInsensitiveCompare(tag) == .orderedSame &&
            !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        return candidates.sorted { left, right in
            if left.identifier == right.identifier { return false }
            if left.quality != right.quality { return left.quality.rawValue > right.quality.rawValue }
            // Preserve the system's selection among equally good installed voices.
            if left.identifier == fallback?.identifier { return true }
            if right.identifier == fallback?.identifier { return false }
            return left.identifier < right.identifier
        }.first ?? fallback
    }
}
