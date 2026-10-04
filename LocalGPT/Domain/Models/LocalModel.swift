import Foundation

/// A model that runs on this device. The first one is Apple's system model
/// (Foundation Models `SystemLanguageModel`); the type stays a list so an
/// open-weight local model can join later without changing the UI.
struct LocalModel: Identifiable, Hashable, Codable, Sendable {
    /// Mirrors `SystemLanguageModel.availability`.
    enum Availability: Codable, Sendable {
        /// `.available`
        case ready
        /// `.unavailable(.modelNotReady)`: the system is still fetching assets.
        case preparing
        /// `.unavailable(.appleIntelligenceNotEnabled)`: the person has to turn it on.
        case needsSetup
        /// `.unavailable(.deviceNotEligible)`
        case unsupported
    }

    let id: String
    /// Full name, shown in the model sheet.
    var name: String
    /// Short label, shown in the composer.
    var shortName: String
    /// Accepts images directly, so screenshots need no separate text extraction.
    var readsImages: Bool
    var availability: Availability
}
