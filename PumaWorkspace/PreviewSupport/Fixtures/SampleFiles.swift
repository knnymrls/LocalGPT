#if DEBUG
import UIKit

/// Real files behind the sample attachments, written once into the caches
/// folder so they open in the system viewer like an imported file would.
enum SampleFiles {
    struct File {
        var url: URL
        /// A small encoded image for a photo's card.
        var thumbnail: Data?
    }

    static let harbor = pdf(named: "Harbor Hall proposal.pdf", text: Fixtures.harborText)
    static let riverside = text(named: "Riverside Loft proposal.txt", Fixtures.riversideText)
    static let guestUpdate = screenshot(named: "Guest count update.png", text: Fixtures.guestUpdateText)
    static let catering = text(named: "Catering quotes.csv", Fixtures.cateringCSV)
    static let notes = text(named: "Planning notes.md", Fixtures.planningNotes)

    private static func destination(_ name: String) -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }

    private static func text(named name: String, _ contents: String) -> File? {
        let url = destination(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return File(url: url)
        } catch {
            return nil
        }
    }

    /// A one-page US Letter PDF: the first line as a title, the rest as body.
    private static func pdf(named name: String, text: String) -> File? {
        let url = destination(name)
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let lines = text.components(separatedBy: "\n")
        let title = lines.first ?? ""
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { context in
                context.beginPage()
                let margin: CGFloat = 72
                let width = page.width - margin * 2
                (title as NSString).draw(
                    in: CGRect(x: margin, y: margin, width: width, height: 40),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold)]
                )
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 5
                (body as NSString).draw(
                    in: CGRect(x: margin, y: margin + 56, width: width, height: page.height - margin * 2 - 56),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 13), .paragraphStyle: paragraph]
                )
            }
            return File(url: url)
        } catch {
            return nil
        }
    }

    /// A PNG that looks like a screenshot of one message.
    private static func screenshot(named name: String, text: String) -> File? {
        let url = destination(name)
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let bubble = CGRect(x: 40, y: 190, width: 520, height: 220)
            UIColor(white: 0.93, alpha: 1).setFill()
            UIBezierPath(roundedRect: bubble, cornerRadius: 36).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6
            (text as NSString).draw(
                in: bubble.insetBy(dx: 32, dy: 30),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 27), .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph,
                ]
            )
        }
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return nil }
        return File(url: url, thumbnail: image.jpegData(compressionQuality: 0.8))
    }
}
#endif
