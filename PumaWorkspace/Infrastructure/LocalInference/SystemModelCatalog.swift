import Foundation
import FoundationModels

struct SystemModelCatalog: ModelCatalog {
    static let modelID = "apple.system.on-device"
    var defaultModelID: String { Self.modelID }
    func models() async -> [LocalModel] {
        let availability: LocalModel.Availability
        switch SystemLanguageModel.default.availability {
        case .available: availability = .ready
        case .unavailable(.appleIntelligenceNotEnabled): availability = .needsSetup
        case .unavailable(.modelNotReady): availability = .preparing
        case .unavailable: availability = .unsupported
        }
        return [LocalModel(id:Self.modelID,name:"Apple on-device model",shortName:"On-device",readsImages:false,availability:availability)]
    }
}

extension LocalModel.Availability {
    var explanation: String? {
        switch self {
        case .ready: nil
        case .needsSetup: "Enable Apple Intelligence in Settings to use the on-device assistant."
        case .preparing: "The on-device model is still preparing. Keep this device connected to power and Wi-Fi, then try again."
        case .unsupported: "The on-device model is unavailable on this device or Simulator runtime."
        }
    }
}
