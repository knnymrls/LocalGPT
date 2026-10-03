import Foundation

/// Perceptual meter: ordinary speech must move the waveform without pretending silence is speech.
enum MicrophoneLevel {
    static func normalized(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 55) / 43))
    }
}
