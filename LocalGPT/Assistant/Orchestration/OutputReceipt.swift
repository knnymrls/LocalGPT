import Foundation

/// A receipt reports persisted files, independently of the model's final prose.
enum OutputReceipt {
    static func text(_ outputs: [Attachment]) -> String {
        "Created " + outputs.map(\.name).joined(separator: ", ")
            + ". Open the files below or in Outputs to inspect and share them."
    }
}
