import Foundation

/// Until the app is built with the image-capable SDK, do not present OCR as scene understanding.
enum ImageInputSupport {
    static let explanation =
        "I received your photo. This build can read text in images, but it cannot identify objects or describe the scene yet. You can ask me to extract or summarize any visible text."

    static func needsVisualUnderstanding(_ prompt: String) -> Bool {
        let text = prompt.lowercased().replacingOccurrences(of: "’", with: "'")
        if text.range(of: #"\b(read|extract|transcribe|text|words|receipt|summarize)\b"#, options: .regularExpression)
            != nil
        {
            return false
        }
        let direct =
            text.range(
                of: #"what('s| is| are)\s+(this|that|these|those|it)\b|what (do|can) you see"#,
                options: .regularExpression) != nil
        let imageReference =
            text.range(
                of: #"\b(photo|image|picture|screenshot|attachment|scene|object)\b"#,
                options: .regularExpression) != nil
        let visualRequest =
            text.range(
                of: #"\b(what|describe|identify|recognize|recognise|look)\b"#,
                options: .regularExpression) != nil
        return direct || (imageReference && visualRequest)
    }
}
