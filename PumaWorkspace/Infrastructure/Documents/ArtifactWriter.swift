import Foundation
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

actor ArtifactWriter {
    let files: WorkspaceFiles
    let repository: any AttachmentRepository
    let database: WorkspaceDatabase
    init(files: WorkspaceFiles, repository: any AttachmentRepository, database: WorkspaceDatabase) {
        self.files = files; self.repository = repository; self.database = database
    }

    func document(name: String, format: String, content: String, conversationID: UUID, scope: RequestScope) async throws -> Attachment {
        try scope.check()
        guard content.utf8.count <= 200_000 else { throw WorkspaceError.message("The generated file is too large. Create it in smaller sections.") }
        let ext = format.lowercased()
        guard ["txt","md","json","csv","r","pdf"].contains(ext) else { throw WorkspaceError.message("Unsupported output format.") }
        if ext == "json" { _ = try JSONSerialization.jsonObject(with:Data(content.utf8),options:.fragmentsAllowed) }
        if ext == "csv" { _ = try CSVTable.parse(content) }
        let data = ext == "pdf" ? try Self.pdf(content) : Data(content.utf8)
        return try await store(data,name:name,extension:ext,text:content,conversationID:conversationID,scope:scope)
    }

    func chart(name: String, labels: [String], values: [Double], conversationID: UUID, scope: RequestScope) async throws -> Attachment {
        guard labels.count == values.count, (1...30).contains(values.count), values.allSatisfy({$0.isFinite && $0 >= 0}) else {
            throw WorkspaceError.message("A chart needs 1–30 matching labels and finite, nonnegative values.")
        }
        try scope.check()
        let width = 1200, height = max(500, 130 + labels.count * 52)
        let data = try Self.png(width:width,height:height) { context in
            Self.drawText(name,at:CGPoint(x:40,y:CGFloat(height-55)),size:24,context:context)
            let maximum = max(values.max() ?? 1,1)
            for i in labels.indices {
                let y = CGFloat(height-120-i*52)
                Self.drawText(String(labels[i].prefix(28)),at:CGPoint(x:40,y:y+8),size:16,context:context)
                context.setFillColor(CGColor(red:0.18,green:0.3,blue:0.4,alpha:1))
                context.fill(CGRect(x:320,y:y,width:CGFloat(values[i]/maximum)*720,height:30))
                Self.drawText(values[i].formatted(),at:CGPoint(x:1050,y:y+8),size:15,context:context)
            }
        }
        let text = ([name] + zip(labels, values).map { "\($0): \($1)" }).joined(separator: "\n")
        return try await store(data,name:name,extension:"png",text:text,conversationID:conversationID,scope:scope)
    }

    func diagram(name: String, steps: [String], conversationID: UUID, scope: RequestScope) async throws -> Attachment {
        guard (1...12).contains(steps.count), steps.allSatisfy({$0.count <= 100}) else { throw WorkspaceError.message("A diagram supports up to 12 short steps.") }
        try scope.check()
        let height = 150 + steps.count * 120
        let data = try Self.png(width:1000,height:height) { context in
            Self.drawText(name,at:CGPoint(x:50,y:CGFloat(height-60)),size:26,context:context)
            for i in steps.indices {
                let y = CGFloat(height-180-i*120)
                context.setFillColor(CGColor(gray:0.94,alpha:1))
                context.fill(CGRect(x:50,y:y,width:900,height:70))
                Self.drawText(String(steps[i].prefix(85)),at:CGPoint(x:70,y:y+28),size:17,context:context)
                if i < steps.count-1 {
                    context.setStrokeColor(CGColor(gray:0.3,alpha:1));context.setLineWidth(2)
                    context.move(to:CGPoint(x:500,y:y-5));context.addLine(to:CGPoint(x:500,y:y-43))
                    context.addLine(to:CGPoint(x:491,y:y-32));context.move(to:CGPoint(x:500,y:y-43));context.addLine(to:CGPoint(x:509,y:y-32));context.strokePath()
                }
            }
        }
        return try await store(data,name:name,extension:"png",text:([name] + steps).joined(separator: "\n"),conversationID:conversationID,scope:scope)
    }

    private func store(_ data: Data, name: String, extension ext: String, text: String, conversationID: UUID, scope: RequestScope) async throws -> Attachment {
        try scope.check()
        let basename = (WorkspaceFiles.safeName(name) as NSString).deletingPathExtension
        var item = Attachment(name:basename+"."+ext,kind:.init(fileExtension:ext),readiness:.ready)
        item.conversationID = conversationID; item.isGenerated = true
        item.previewText = String(text.prefix(12000))
        item.fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        item.fileURL = try files.write(data,id:item.id,name:item.name)
        do {
            try scope.check()
            let passages = LocalDocumentImporter.chunks(text).enumerated().map {
                SourcePassage(sourceID: item.id, locator: "Generated content · passage \($0.offset + 1)", text: $0.element)
            }
            try await database.index(passages, sourceID: item.id, fingerprint: "generated-v1-\(item.id)")
            try scope.check()
            try await repository.save(item)
        } catch {
            try? await repository.delete(id: item.id)
            try? files.remove(id:item.id)
            throw error
        }
        return item
    }

    static func pdf(_ content: String) throws -> Data {
        let data = NSMutableData()
        var media = CGRect(x:0,y:0,width:612,height:792)
        guard let consumer = CGDataConsumer(data:data), let context = CGContext(consumer:consumer,mediaBox:&media,nil) else {
            throw WorkspaceError.message("Could not create the PDF.")
        }
        let text = NSAttributedString(string:content,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,12,nil)])
        let setter = CTFramesetterCreateWithAttributedString(text)
        var offset = 0, page = 0
        repeat {
            guard page < 100 else { throw WorkspaceError.message("This PDF exceeds 100 pages.") }
            context.beginPDFPage(nil)
            let path = CGPath(rect:CGRect(x:44,y:54,width:524,height:680),transform:nil)
            let frame = CTFramesetterCreateFrame(setter,CFRange(location:offset,length:0),path,nil)
            CTFrameDraw(frame,context)
            let length = CTFrameGetVisibleStringRange(frame).length
            Self.drawText("\(page+1)",at:CGPoint(x:300,y:25),size:10,context:context)
            context.endPDFPage()
            guard length > 0 || text.length == 0 else { throw WorkspaceError.message("Unable to lay out the PDF text.") }
            offset += length;page += 1
        } while offset < text.length
        context.closePDF()
        return data as Data
    }

    private static func png(width:Int,height:Int,draw:(CGContext)->Void) throws -> Data {
        guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw WorkspaceError.message("Could not render the image.") }
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
        draw(context)
        let data = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else { throw WorkspaceError.message("Could not encode the image.") }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw WorkspaceError.message("Could not save the image.") }
        return data as Data
    }

    private static func drawText(_ text:String,at point:CGPoint,size:CGFloat,context:CGContext) {
        let text = NSAttributedString(string:text,attributes:[
            NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,size,nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0.12,alpha:1)])
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(text),context)
    }
}
