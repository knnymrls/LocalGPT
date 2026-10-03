import SwiftUI

// MARK: - The icon set, as vectors
//
// Ported from Slashy origin/main:mobile/ios-messages-extension/NucleoIcons.swift.
// Every glyph is a Nucleo UI icon from Slashy's
// `mobile/components/icons/nucleo/<Name>Icon.tsx` (18-unit viewBox). No SF
// Symbols: Apple's glyphs read as a different product next to Nucleo's.
//
// The path data comes across verbatim. Rather than hand-translate curves into
// `Path` calls — which is where transcription errors hide — the `d` strings
// (and Line / Polyline / Rect / Circle attributes) are copied byte-for-byte
// from the .tsx sources and parsed at draw time. Diffing against Slashy is a
// string comparison.

// MARK: - SVG path data → Path

/// The subset of SVG path grammar this artwork uses: M m L l H h V v C c S s
/// Q q T t A a Z z. Arcs are converted to cubics rather than drawn through
/// `CGPath`'s arc primitives, which take a center and cannot express SVG's
/// endpoint parameterization without the same conversion anyway.
enum SVGPath {
    static func build(_ d: String) -> Path {
        var path = Path()
        var cursor = Cursor(d)
        var command: Character = "M"
        var point = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?

        func relative(_ x: CGFloat, _ y: CGFloat, _ isRelative: Bool) -> CGPoint {
            isRelative ? CGPoint(x: point.x + x, y: point.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            cursor.skipSeparators()
            guard !cursor.isAtEnd else { break }

            if cursor.peekIsLetter {
                command = cursor.takeLetter()
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    point = subpathStart
                    lastCubicControl = nil
                    lastQuadControl = nil
                    continue
                }
            }

            let isRelative = command.isLowercase
            var consumed = true

            switch Character(command.lowercased()) {
            case "m":
                guard let x = cursor.number(), let y = cursor.number() else { consumed = false; break }
                point = relative(x, y, isRelative)
                path.move(to: point)
                subpathStart = point
                lastCubicControl = nil
                lastQuadControl = nil
                // Per SVG: coordinate pairs after a moveto are implicit linetos.
                command = isRelative ? "l" : "L"

            case "l":
                guard let x = cursor.number(), let y = cursor.number() else { consumed = false; break }
                point = relative(x, y, isRelative)
                path.addLine(to: point)
                lastCubicControl = nil
                lastQuadControl = nil

            case "h":
                guard let x = cursor.number() else { consumed = false; break }
                point = CGPoint(x: isRelative ? point.x + x : x, y: point.y)
                path.addLine(to: point)
                lastCubicControl = nil
                lastQuadControl = nil

            case "v":
                guard let y = cursor.number() else { consumed = false; break }
                point = CGPoint(x: point.x, y: isRelative ? point.y + y : y)
                path.addLine(to: point)
                lastCubicControl = nil
                lastQuadControl = nil

            case "c":
                guard
                    let x1 = cursor.number(), let y1 = cursor.number(),
                    let x2 = cursor.number(), let y2 = cursor.number(),
                    let x = cursor.number(), let y = cursor.number()
                else { consumed = false; break }
                let c1 = relative(x1, y1, isRelative)
                let c2 = relative(x2, y2, isRelative)
                point = relative(x, y, isRelative)
                path.addCurve(to: point, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil

            case "s":
                guard
                    let x2 = cursor.number(), let y2 = cursor.number(),
                    let x = cursor.number(), let y = cursor.number()
                else { consumed = false; break }
                // The first control is the reflection of the previous one; with
                // no previous cubic it coincides with the current point.
                let c1 = reflect(lastCubicControl, about: point)
                let c2 = relative(x2, y2, isRelative)
                point = relative(x, y, isRelative)
                path.addCurve(to: point, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil

            case "q":
                guard
                    let x1 = cursor.number(), let y1 = cursor.number(),
                    let x = cursor.number(), let y = cursor.number()
                else { consumed = false; break }
                let c1 = relative(x1, y1, isRelative)
                point = relative(x, y, isRelative)
                path.addQuadCurve(to: point, control: c1)
                lastQuadControl = c1
                lastCubicControl = nil

            case "t":
                guard let x = cursor.number(), let y = cursor.number() else { consumed = false; break }
                let c1 = reflect(lastQuadControl, about: point)
                point = relative(x, y, isRelative)
                path.addQuadCurve(to: point, control: c1)
                lastQuadControl = c1
                lastCubicControl = nil

            case "a":
                guard
                    let rx = cursor.number(), let ry = cursor.number(),
                    let rotation = cursor.number(),
                    let largeArc = cursor.flag(), let sweep = cursor.flag(),
                    let x = cursor.number(), let y = cursor.number()
                else { consumed = false; break }
                let end = relative(x, y, isRelative)
                addArc(
                    to: &path, from: point, rx: rx, ry: ry, rotationDegrees: rotation,
                    largeArc: largeArc != 0, sweep: sweep != 0, end: end
                )
                point = end
                lastCubicControl = nil
                lastQuadControl = nil

            default:
                consumed = false
            }

            // Malformed data would otherwise spin here forever.
            if !consumed { break }
        }

        return path
    }

    private static func reflect(_ control: CGPoint?, about point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    /// SVG F.6.5 endpoint → center parameterization, then F.6.6 out-of-range
    /// radius correction, emitted as ≤90° cubic segments.
    private static func addArc(
        to path: inout Path,
        from start: CGPoint,
        rx rxIn: CGFloat,
        ry ryIn: CGFloat,
        rotationDegrees: CGFloat,
        largeArc: Bool,
        sweep: Bool,
        end: CGPoint
    ) {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        // A zero radius is a straight line, per spec — not a degenerate arc.
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)

        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard length > 0 else { return 0 }
            var value = acos(min(1, max(-1, (ux * vx + uy * vy) / length)))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var sweepAngle = angle(ux, uy, vx, vy)
        if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }

        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        // The magic constant that makes a cubic match a circular arc of `delta`.
        let alpha = 4.0 / 3.0 * tan(delta / 4)

        func point(at theta: CGFloat) -> CGPoint {
            CGPoint(
                x: cx + rx * cos(theta) * cosPhi - ry * sin(theta) * sinPhi,
                y: cy + rx * cos(theta) * sinPhi + ry * sin(theta) * cosPhi
            )
        }
        func derivative(at theta: CGFloat) -> CGPoint {
            CGPoint(
                x: -rx * sin(theta) * cosPhi - ry * cos(theta) * sinPhi,
                y: -rx * sin(theta) * sinPhi + ry * cos(theta) * cosPhi
            )
        }

        var theta = theta1
        for _ in 0..<segments {
            let next = theta + delta
            let p1 = point(at: theta)
            let p2 = point(at: next)
            let d1 = derivative(at: theta)
            let d2 = derivative(at: next)
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
                control2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y)
            )
            theta = next
        }
    }

    /// Character-level scanner. Path data packs numbers without separators
    /// (`13.470-.293`, `.75.75`), so a whitespace split cannot read it.
    private struct Cursor {
        private let characters: [Character]
        private var index = 0

        init(_ string: String) {
            characters = Array(string)
        }

        var isAtEnd: Bool { index >= characters.count }

        var peekIsLetter: Bool {
            index < characters.count && characters[index].isLetter
        }

        mutating func takeLetter() -> Character {
            let character = characters[index]
            index += 1
            return character
        }

        mutating func skipSeparators() {
            while index < characters.count,
                  characters[index] == " " || characters[index] == ","
                    || characters[index] == "\n" || characters[index] == "\t"
                    || characters[index] == "\r" {
                index += 1
            }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = index
            if index < characters.count, characters[index] == "+" || characters[index] == "-" {
                index += 1
            }
            var sawDigit = false
            while index < characters.count, characters[index].isASCIIDigit {
                index += 1
                sawDigit = true
            }
            if index < characters.count, characters[index] == "." {
                index += 1
                while index < characters.count, characters[index].isASCIIDigit {
                    index += 1
                    sawDigit = true
                }
            }
            if sawDigit, index < characters.count,
               characters[index] == "e" || characters[index] == "E" {
                let beforeExponent = index
                index += 1
                if index < characters.count, characters[index] == "+" || characters[index] == "-" {
                    index += 1
                }
                var sawExponentDigit = false
                while index < characters.count, characters[index].isASCIIDigit {
                    index += 1
                    sawExponentDigit = true
                }
                if !sawExponentDigit { index = beforeExponent }
            }
            guard sawDigit else {
                index = start
                return nil
            }
            return CGFloat(Double(String(characters[start..<index])) ?? 0)
        }

        /// Arc flags are single characters and may be packed against the next
        /// number (`0 0 1 5.5` can appear as `001 5.5`), so they cannot go
        /// through `number()`.
        mutating func flag() -> CGFloat? {
            skipSeparators()
            guard index < characters.count else { return nil }
            if characters[index] == "0" || characters[index] == "1" {
                let value: CGFloat = characters[index] == "1" ? 1 : 0
                index += 1
                return value
            }
            return number()
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}

// MARK: - Icon model

/// One drawable element of an icon, and how it is inked.
struct VectorElement: Sendable {
    enum Geometry: Sendable {
        case path(String)
        case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
        case roundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat)
        /// SVG `<Line>`.
        case line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
        /// SVG `<Polyline points="…">`, the attribute string verbatim.
        case polyline(String)
    }

    enum Paint: Sendable {
        /// `fill-rule` matters where a glyph overlaps itself; nucleo's filled
        /// variants are nonzero except where the source says otherwise.
        case fill(evenOdd: Bool = false)
        /// Width in viewBox units — scaled with the glyph, so a 1.5 stroke in
        /// an 18-box drawn at 20pt lands at 1.67pt, exactly as the app's does.
        case stroke(width: CGFloat)
        /// `fill={color} stroke={color}` — the outline AI sparkle and the
        /// More dots, which are filled and then stroked to round them out.
        case fillAndStroke(width: CGFloat)
    }

    var geometry: Geometry
    var paint: Paint = .fill()

    func makePath() -> Path {
        switch geometry {
        case .path(let data):
            return SVGPath.build(data)
        case .circle(let cx, let cy, let r):
            return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        case .roundedRect(let x, let y, let width, let height, let radius):
            return Path(
                roundedRect: CGRect(x: x, y: y, width: width, height: height),
                cornerRadius: radius
            )
        case .line(let x1, let y1, let x2, let y2):
            var path = Path()
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
            return path
        case .polyline(let points):
            let values = points
                .split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }
            var path = Path()
            var index = 0
            while index + 1 < values.count {
                let point = CGPoint(x: values[index], y: values[index + 1])
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                index += 2
            }
            return path
        }
    }
}

struct VectorIcon: Sendable {
    /// The source viewBox edge. Nucleo is 18.
    var viewBox: CGFloat = 18
    var elements: [VectorElement]
}

/// One element, scaled from its viewBox into the frame it is given.
private struct VectorElementShape: Shape {
    let element: VectorElement
    let viewBox: CGFloat

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        return element.makePath().applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// An icon drawn at a point size, in one ink — the app's `<Icon color size />`.
struct VectorIconView: View {
    let icon: VectorIcon
    var size: CGFloat = 24
    var color: Color

    var body: some View {
        ZStack {
            ForEach(icon.elements.indices, id: \.self) { index in
                let element = icon.elements[index]
                let shape = VectorElementShape(element: element, viewBox: icon.viewBox)
                switch element.paint {
                case .fill(let evenOdd):
                    shape.fill(color, style: FillStyle(eoFill: evenOdd))
                case .stroke(let width):
                    shape.stroke(color, style: strokeStyle(width))
                case .fillAndStroke(let width):
                    shape.fill(color)
                        .overlay(shape.stroke(color, style: strokeStyle(width)))
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func strokeStyle(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width * (size / icon.viewBox), lineCap: .round, lineJoin: .round)
    }
}

// MARK: - Public API

/// The Puma icon set. Each case names its Slashy source, `<Name>Icon.tsx`.
enum NucleoIcon: String, CaseIterable, Sendable {
    case menuLines, composePen, paperclip, add, microphone, microphoneSlash, keyboard
    case arrowUp, stop, waveform, xmark, done, chevronDown, chevronLeft, chevronRight
    case swap, clock, history, trash, ai, images, camera, folder, copy, comment
    case draft, search, more, gear, refresh
    case menuLeft, chatTask, ballotCircle, pinTack, pen, speaker, play, pause, skipBack, skipForward, brain
    // File types, one glyph each.
    case fileImage, filePDF, fileDocument, fileSpreadsheet, fileMarkdown, fileText
    case fileCode, filePresentation, fileArchive, fileAudio, fileVideo, fileGeneric

    /// The default (outline) render — what the .tsx draws with `filled` unset.
    var outline: VectorIcon { NucleoGlyphs.outline(self) }

    /// The `filled` render where the .tsx has one; otherwise the outline.
    var filled: VectorIcon { NucleoGlyphs.filled(self) ?? NucleoGlyphs.outline(self) }
}

/// A Nucleo glyph at a point size, in one ink. Decorative by default; give the
/// enclosing control its accessibility label.
struct Icon: View {
    let icon: NucleoIcon
    var size: CGFloat
    var color: Color
    var filled: Bool

    init(_ icon: NucleoIcon, size: CGFloat = 20, color: Color = Tokens.foreground, filled: Bool = false) {
        self.icon = icon
        self.size = size
        self.color = color
        self.filled = filled
    }

    var body: some View {
        // `size` is the iPhone 17 Pro baseline; it scales with the device like
        // type and controls do. Callers pass plain design points.
        VectorIconView(icon: filled ? icon.filled : icon.outline, size: size * Tokens.uiScale, color: color)
            .accessibilityHidden(true)
    }
}

// MARK: - The set
//
// Path data below is VERBATIM from the .tsx sources named in each case.
// Do not reformat it — a diff against Slashy should be a string comparison.
// Outline elements are stroked at the .tsx default `strokeWidth = 1.5`.

private enum NucleoGlyphs {
    private static let w: CGFloat = 1.5

    private static func s(_ d: String) -> VectorElement {
        VectorElement(geometry: .path(d), paint: .stroke(width: w))
    }

    private static func f(_ d: String, evenOdd: Bool = false) -> VectorElement {
        VectorElement(geometry: .path(d), paint: .fill(evenOdd: evenOdd))
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> VectorElement {
        VectorElement(geometry: .line(x1: x1, y1: y1, x2: x2, y2: y2), paint: .stroke(width: w))
    }

    private static func poly(_ points: String) -> VectorElement {
        VectorElement(geometry: .polyline(points), paint: .stroke(width: w))
    }

    private static func rect(
        _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, rx: CGFloat,
        paint: VectorElement.Paint = .stroke(width: w)
    ) -> VectorElement {
        VectorElement(geometry: .roundedRect(x: x, y: y, width: width, height: height, radius: rx), paint: paint)
    }

    private static func circle(
        _ cx: CGFloat, _ cy: CGFloat, r: CGFloat, paint: VectorElement.Paint = .stroke(width: w)
    ) -> VectorElement {
        VectorElement(geometry: .circle(cx: cx, cy: cy, r: r), paint: paint)
    }

    // swiftlint:disable function_body_length line_length
    static func outline(_ icon: NucleoIcon) -> VectorIcon {
        switch icon {
        case .fileImage: // nucleo-ui-outline-18 — IconImageOutline18, verbatim
            return VectorIcon(elements: [
                s("M3.762,14.989l6.074-6.075c.781-.781,2.047-.781,2.828,0l2.586,2.586"),
                rect(2.75, 2.75, 12.5, 12.5, rx: 2),
                circle(6.25, 7.25, r: 1.25, paint: .fill()),
            ])
        case .filePDF: // nucleo-ui-outline-18 — IconPageOutline18
            // The source's outer rect carries `translate(18 0) rotate(90)`;
            // it is written here already rotated, as the portrait page.
            return VectorIcon(elements: [
                line(10.25, 6.25, 12.25, 6.25),
                line(5.75, 9.25, 12.25, 9.25),
                line(5.75, 12.25, 12.25, 12.25),
                rect(2.75, 1.75, 12.5, 14.5, rx: 2),
                rect(5.75, 4.75, 1.5, 1.5, rx: 0, paint: .fillAndStroke(width: w)),
            ])
        case .fileDocument: // nucleo-ui-outline-18 — IconPage2Outline18, verbatim
            return VectorIcon(elements: [
                line(5.75, 11.25, 9, 11.25),
                line(5.75, 8.25, 12.25, 8.25),
                line(5.75, 5.25, 12.25, 5.25),
                rect(2.75, 1.75, 12.5, 14.5, rx: 2),
            ])
        case .fileSpreadsheet: // nucleo-ui-outline-18 — IconReportOutline18, verbatim
            return VectorIcon(elements: [
                s("m15.16,6.25h-3.41c-.552,0-1-.448-1-1V1.852"),
                s("m2.75,14.25V3.75c0-1.105.895-2,2-2h5.586c.265,0,.52.105.707.293l3.914,3.914c.188.188.293.442.293.707v7.586c0,1.105-.895,2-2,2H4.75c-1.105,0-2-.895-2-2Z"),
                line(9, 13.25, 9, 8),
                line(6.25, 13.25, 6.25, 10.5),
                line(11.75, 13.25, 11.75, 11.75),
            ])
        case .fileMarkdown: // nucleo-ui-outline-18 — IconMarkdownOutline18, verbatim
            return VectorIcon(elements: [
                rect(0.75, 3.75, 16.5, 10.5, rx: 2),
                poly("8.75 11.25 8.75 6.75 8.356 6.75 6.25 9.5 4.144 6.75 3.75 6.75 3.75 11.25"),
                poly("11.5 9.5 13.25 11.25 15 9.5"),
                line(13.25, 11.25, 13.25, 6.75),
            ])
        case .fileText: // nucleo-ui-outline-18 — IconScrollTextOutline18, verbatim
            return VectorIcon(elements: [
                s("M14.75,15.75c.828,0,1.5-.672,1.5-1.5v-1c0-.276-.224-.5-.5-.5h-7.5c-.276,0-.5,.224-.5,.5v1c0,.828-.672,1.5-1.5,1.5h0c-.828,0-1.5-.672-1.5-1.5V3.75c0-.828-.672-1.5-1.5-1.5h0c-.828,0-1.5,.672-1.5,1.5v2c0,.552,.448,1,1,1h2"),
                line(14.75, 15.75, 6.25, 15.75),
                s("M3.25,2.25H12.75c.828,0,1.5,.672,1.5,1.5v6.5"),
                line(7.5, 5.75, 11.5, 5.75),
                line(7.5, 8.75, 11.5, 8.75),
            ])
        case .fileCode: // nucleo-ui-outline-18 — IconCodeOutline18, verbatim
            return VectorIcon(elements: [
                poly("6.5 13.75 1.75 9 6.5 4.25"),
                poly("11.5 13.75 16.25 9 11.5 4.25"),
            ])
        case .filePresentation: // nucleo-ui-outline-18 — IconSlideshowOutline18, verbatim
            return VectorIcon(elements: [
                circle(5, 16, r: 1, paint: .fill()),
                circle(13, 16, r: 1, paint: .fill()),
                circle(9, 16, r: 1.25, paint: .fill()),
                rect(1.75, 2.75, 14.5, 10, rx: 2),
            ])
        case .fileArchive: // nucleo-ui-outline-18 — IconFileZipOutline18, verbatim
            return VectorIcon(elements: [
                s("M2.75,14.25V3.75c0-1.105,.895-2,2-2h5.586c.265,0,.52,.105,.707,.293l3.914,3.914c.188,.188,.293,.442,.293,.707v7.586c0,1.105-.895,2-2,2H4.75c-1.105,0-2-.895-2-2Z"),
                s("M15.16,6.25h-3.41c-.552,0-1-.448-1-1V1.852"),
                rect(5, 2.5, 2, 1.5, rx: 0, paint: .fill()),
                rect(7, 4, 2, 1.5, rx: 0, paint: .fill()),
                rect(5, 5.5, 2, 1.5, rx: 0, paint: .fill()),
                rect(7, 7, 2, 1.5, rx: 0, paint: .fill()),
                s("M7,9.75h0c.69,0,1.25,.56,1.25,1.25v2.25h-2.5v-2.25c0-.69,.56-1.25,1.25-1.25Z"),
            ])
        case .fileAudio: // nucleo-ui-outline-18 — IconFileMusicOutline18, verbatim
            return VectorIcon(elements: [
                s("M5.75 6.75H7.75"),
                s("M5.75 9.75H10.25"),
                s("M15.16 6.24999H11.75C11.198 6.24999 10.75 5.80199 10.75 5.24999V1.85199"),
                s("M13.25 17.25C14.078 17.25 14.75 16.578 14.75 15.75C14.75 14.922 14.078 14.25 13.25 14.25C12.422 14.25 11.75 14.922 11.75 15.75C11.75 16.578 12.422 17.25 13.25 17.25Z"),
                s("M15.25 7.7974V6.6641C15.25 6.399 15.145 6.1441 14.957 5.9571L11.043 2.043C10.855 1.855 10.601 1.75 10.336 1.75H4.75C3.645 1.75 2.75 2.646 2.75 3.75V14.25C2.75 15.354 3.645 16.25 4.75 16.25H8.80051"),
                s("M14.75 15.75V10.75C15.067 11.073 15.48 11.442 16 11.797C16.45 12.104 16.879 12.332 17.25 12.5"),
            ])
        case .fileVideo: // nucleo-ui-outline-18 — IconFilePlayOutline18, verbatim
            return VectorIcon(elements: [
                s("M5.75 6.75H7.75"),
                s("M5.75 9.75H10.25"),
                s("M15.16 6.25H11.75C11.198 6.25 10.75 5.802 10.75 5.25V1.85201"),
                s("M12.539 11.323L16.743 13.8C17.086 14.002 17.086 14.497 16.743 14.699L12.539 17.176C12.19 17.382 11.75 17.131 11.75 16.727V11.772C11.75 11.368 12.191 11.117 12.539 11.323Z"),
                s("M15.25 9.43851V6.66409C15.25 6.39899 15.145 6.14411 14.957 5.95711L11.043 2.043C10.855 1.855 10.601 1.75 10.336 1.75H4.75C3.645 1.75 2.75 2.646 2.75 3.75V14.25C2.75 15.354 3.645 16.25 4.75 16.25H8.75"),
            ])
        case .fileGeneric: // nucleo-ui-outline-18 — IconFileOutline18, verbatim
            return VectorIcon(elements: [
                s("M15.16,6.25h-3.41c-.552,0-1-.448-1-1V1.852"),
                s("M2.75,14.25V3.75c0-1.105,.895-2,2-2h5.586c.265,0,.52,.105,.707,.293l3.914,3.914c.188,.188,.293,.442,.293,.707v7.586c0,1.105-.895,2-2,2H4.75c-1.105,0-2-.895-2-2Z"),
            ])
        case .play: // nucleo-ui-fill-18 — IconMediaPlayFill18, verbatim
            return VectorIcon(elements: [
                f("M15.1,7.478L5.608,2.222c-.553-.306-1.206-.297-1.749,.023-.538,.317-.859,.877-.859,1.499V14.256c0,.622,.321,1.182,.859,1.499,.279,.164,.586,.247,.895,.247,.293,0,.586-.075,.854-.223l9.491-5.256c.556-.307,.901-.891,.901-1.522s-.345-1.215-.9-1.522Z"),
            ])
        case .pause: // nucleo-ui-fill-18 — IconMediaPauseFill18, verbatim
            return VectorIcon(elements: [
                rect(2, 2, 5, 14, rx: 1.75, paint: .fill()),
                rect(11, 2, 5, 14, rx: 1.75, paint: .fill()),
            ])
        case .brain: // nucleo-ui-outline-18 — IconBrainOutline18, verbatim
            return VectorIcon(elements: [
                s("M9 4.5C9 3.257 10.007 2.25 11.25 2.25C12.493 2.25 13.5 3.257 13.5 4.5C13.5 4.593 13.484 4.682 13.473 4.772C14.748 4.886 15.75 5.945 15.75 7.25C15.75 8.27 15.137 9.145 14.261 9.533C14.85 9.881 15.25 10.516 15.25 11.25C15.25 12.278 14.471 13.115 13.473 13.228C13.484 13.318 13.5 13.407 13.5 13.5C13.5 14.743 12.493 15.75 11.25 15.75C10.007 15.75 9 14.743 9 13.5"),
                s("M5.49998 9.75H4.74998C4.38898 9.75 4.04499 9.673 3.73499 9.536"),
                s("M14.265 9.536C13.955 9.673 13.611 9.75 13.25 9.75H12.5"),
                s("M9 4.5C9 3.257 7.993 2.25 6.75 2.25C5.507 2.25 4.5 3.257 4.5 4.5C4.5 4.593 4.51599 4.682 4.52699 4.772C3.25199 4.886 2.25 5.945 2.25 7.25C2.25 8.27 2.863 9.145 3.739 9.533C3.15 9.881 2.75 10.516 2.75 11.25C2.75 12.278 3.52899 13.115 4.52699 13.228C4.51599 13.318 4.5 13.407 4.5 13.5C4.5 14.743 5.507 15.75 6.75 15.75C7.993 15.75 9 14.743 9 13.5"),
                s("M9 13.5V4.5"),
            ])
        case .skipBack: // nucleo-ui-outline-18 — IconMediaFastBackwardsOutline18, verbatim
            return VectorIcon(elements: [
                s("M9.25,9.572l7.258,4.021c.333,.185,.742-.056,.742-.437V4.844c0-.381-.409-.622-.742-.437l-7.258,4.021"),
                s("M8.508,4.407L1.008,8.563c-.344,.19-.344,.685,0,.875l7.501,4.156c.333,.185,.742-.056,.742-.437V4.844c0-.381-.409-.622-.742-.437Z"),
            ])
        case .skipForward: // nucleo-ui-outline-18 — IconMediaFastForwardOutline18, verbatim
            return VectorIcon(elements: [
                s("M8.75,9.572L1.492,13.593c-.333,.185-.742-.056-.742-.437V4.844c0-.381,.409-.622,.742-.437l7.258,4.021"),
                s("M9.492,4.407l7.501,4.156c.344,.19,.344,.685,0,.875l-7.501,4.156c-.333,.185-.742-.056-.742-.437V4.844c0-.381,.409-.622,.742-.437Z"),
            ])
        case .speaker: // nucleo-ui-outline-18 — IconVolumeUpOutline18, verbatim
            return VectorIcon(elements: [
                s("M5,5.75H2.25c-.828,0-1.5,.672-1.5,1.5v3.5c0,.828,.672,1.5,1.5,1.5h2.75l5.48,3.508c.333,.213,.77-.026,.77-.421V2.664c0-.395-.437-.634-.77-.421l-5.48,3.508Z"),
                s("M13.914,7.586c.781,.781,.781,2.047,0,2.828"),
                s("M15.859,5.641c1.855,1.855,1.855,4.863,0,6.718"),
            ])
        case .menuLeft: // nucleo-ui-outline-18 — IconMenuLeftOutline18, verbatim
            return VectorIcon(elements: [
                line(2.25, 9, 15.75, 9),
                line(2.25, 3.75, 15.75, 3.75),
                line(2.25, 14.25, 8.25, 14.25),
            ])
        case .pinTack: // nucleo-ui-outline-18 — IconPinTackOutline18, verbatim
            return VectorIcon(elements: [
                line(9, 16.25, 9, 12.25),
                s("M14.25,12.25c-.089-.699-.318-1.76-.969-2.875-.335-.574-.703-1.028-1.031-1.375V3.75c0-1.105-.895-2-2-2h-2.5c-1.105,0-2,.895-2,2v4.25c-.329,.347-.697,.801-1.031,1.375-.65,1.115-.88,2.176-.969,2.875H14.25Z"),
            ])
        case .pen: // nucleo-ui-outline-18 — IconPenOutline18, verbatim
            return VectorIcon(elements: [
                s("M2.75,15.25s3.599-.568,4.546-1.515c.947-.947,7.327-7.327,7.327-7.327,.837-.837,.837-2.194,0-3.03-.837-.837-2.194-.837-3.03,0,0,0-6.38,6.38-7.327,7.327s-1.515,4.546-1.515,4.546h0Z"),
            ])
        case .ballotCircle: // nucleo-ui-outline-18 — IconBallotCircleOutline18, verbatim
            return VectorIcon(elements: [
                line(10.5, 5.25, 15.25, 5.25),
                line(10.5, 12.75, 15.25, 12.75),
                circle(5, 5, r: 2.5),
                circle(5, 13, r: 2.5),
            ])
        case .chatTask: // nucleo-ui-outline-18 — IconChatTaskOutline18, verbatim
            return VectorIcon(elements: [
                line(9.75, 11.75, 12.25, 11.75),
                poly("5.75 11.75 8.25 9.25 5.75 6.75"),
                s("m9,1.75C4.996,1.75,1.75,4.996,1.75,9c0,1.319.358,2.552.973,3.617.43.806-.053,2.712-.973,3.633,1.25.068,2.897-.497,3.633-.973.489.282,1.264.656,2.279.848.433.082.881.125,1.338.125,4.004,0,7.25-3.246,7.25-7.25S13.004,1.75,9,1.75Z"),
            ])
        case .menuLines: // MenuLinesIcon.tsx — IconMenu
            return VectorIcon(elements: [
                line(2.25, 9, 15.75, 9),
                line(2.25, 3.75, 15.75, 3.75),
                line(2.25, 14.25, 15.75, 14.25),
            ])
        case .composePen: // ComposePenIcon.tsx — Compose2Outline18
            return VectorIcon(elements: [
                s("M15.25 9.2422V13.25C15.25 14.355 14.355 15.25 13.25 15.25H4.75C3.645 15.25 2.75 14.355 2.75 13.25V4.75C2.75 3.645 3.645 2.75 4.75 2.75H8.75781"),
                s("M7.75 10.25C7.75 10.25 10.0838 10.1662 10.909 9.34101L15.784 4.46601C16.4053 3.84471 16.4053 2.83731 15.784 2.21601C15.1627 1.59471 14.1553 1.59471 13.534 2.21601L8.659 7.09101C7.8809 7.86911 7.75 10.25 7.75 10.25Z"),
            ])
        case .paperclip: // PaperclipIcon.tsx — IconPaperclip
            return VectorIcon(elements: [
                s("M7.75,5v6.75c0,.828,.672,1.5,1.5,1.5h0c.828,0,1.5-.672,1.5-1.5V4.75c0-1.657-1.343-3-3-3h0c-1.657,0-3,1.343-3,3v7c0,2.485,2.015,4.5,4.5,4.5h0c2.485,0,4.5-2.015,4.5-4.5V5"),
            ])
        case .add: // AddIcon.tsx — PlusOutline18
            return VectorIcon(elements: [
                line(9, 3.25, 9, 14.75),
                line(3.25, 9, 14.75, 9),
            ])
        case .microphone: // MicrophoneIcon.tsx
            return VectorIcon(elements: [
                rect(5.75, 1.75, 6.5, 9.5, rx: 3.25),
                s("M15.25,8c0,3.452-2.798,6.25-6.25,6.25h0c-3.452,0-6.25-2.798-6.25-6.25"),
                line(9, 14.25, 9, 16.25),
            ])
        case .microphoneSlash: // MicrophoneSlashIcon.tsx
            return VectorIcon(elements: [
                s("M12.25 5.75V5C12.25 3.2051 10.795 1.75 9 1.75C7.205 1.75 5.75 3.2051 5.75 5V8C5.75 9.1534 6.35079 10.1665 7.25659 10.7433"),
                s("M5.10901 12.891C3.67201 11.746 2.75 9.98 2.75 8"),
                s("M15.25 8C15.25 11.452 12.452 14.25 8.99997 14.25C8.68107 14.25 8.36806 14.2262 8.06226 14.1802"),
                s("M9 14.25V16.25"),
                s("M2 16L16 2"),
            ])
        case .keyboard: // KeyboardIcon.tsx
            return VectorIcon(elements: [
                rect(0.75, 4.75, 16.5, 8.5, rx: 2),
                line(11.75, 10.25, 6.25, 10.25),
                rect(3, 7, 1.5, 1.5, rx: 0.5, paint: .fill()),
                rect(3, 9.5, 1.5, 1.5, rx: 0.5, paint: .fill()),
                rect(5.5, 7, 1.5, 1.5, rx: 0.5, paint: .fill()),
                rect(8.25, 7, 1.5, 1.5, rx: 0.5, paint: .fill()),
                rect(11, 7, 1.5, 1.5, rx: 0.5, paint: .fill()),
                rect(13.5, 7, 1.5, 1.5, rx: 0.5, paint: .fill()),
                rect(13.5, 9.5, 1.5, 1.5, rx: 0.5, paint: .fill()),
            ])
        case .arrowUp: // ArrowUpIcon.tsx
            return VectorIcon(elements: [
                line(9, 2.75, 9, 15.25),
                poly("4.75 7 9 2.75 13.25 7"),
            ])
        case .stop: // StopIcon.tsx
            return VectorIcon(elements: [
                rect(2.75, 2.75, 12.5, 12.5, rx: 2),
            ])
        case .waveform: // WaveformIcon.tsx
            return VectorIcon(elements: [
                line(1.25, 8.25, 1.25, 9.75),
                line(16.25, 8.25, 16.25, 9.75),
                line(4.25, 3.75, 4.25, 14.25),
                line(7.25, 5.75, 7.25, 12.25),
                line(10.25, 2.75, 10.25, 15.25),
                line(13.25, 5.75, 13.25, 12.25),
            ])
        case .xmark: // XmarkIcon.tsx
            return VectorIcon(elements: [
                line(14, 4, 4, 14),
                line(4, 4, 14, 14),
            ])
        case .done: // DoneIcon.tsx
            return VectorIcon(elements: [
                poly("2.75 9.5 6.5 13.25 15.25 4.5"),
            ])
        case .chevronDown: // ChevronDownIcon.tsx
            return VectorIcon(elements: [
                poly("15.25 6.5 9 12.75 2.75 6.5"),
            ])
        case .chevronLeft: // ChevronLeftIcon.tsx
            return VectorIcon(elements: [
                poly("11.5 15.25 5.25 9 11.5 2.75"),
            ])
        case .chevronRight: // ChevronRightIcon.tsx
            return VectorIcon(elements: [
                poly("6.5 2.75 12.75 9 6.5 15.25"),
            ])
        case .swap: // SwapIcon.tsx — outline is the 18-box chevron pair
            return VectorIcon(elements: [
                poly("12.5 6.25 9 2.75 5.5 6.25"),
                poly("12.5 11.75 9 15.25 5.5 11.75"),
            ])
        case .clock: // ClockIcon.tsx
            return VectorIcon(elements: [
                circle(9, 9, r: 7.25),
                poly("9 4.75 9 9 12.25 11.25"),
            ])
        case .history: // HistoryIcon.tsx
            return VectorIcon(elements: [
                s("M1.75281 9.20209C1.85991 13.1127 5.0636 16.25 9 16.25C13.004 16.25 16.25 13.004 16.25 9C16.25 4.996 13.004 1.75 9 1.75C5.9995 1.75 3.42531 3.57271 2.32321 6.17041"),
                s("M1.88 3.30499L2.28799 6.25L5.23199 5.84302"),
                s("M9 4.75V9L12.25 11.25"),
            ])
        case .trash: // TrashIcon.tsx
            return VectorIcon(elements: [
                s("M13.6977 7.75L13.35 14.35C13.294 15.4201 12.416 16.25 11.353 16.25H6.64804C5.58404 16.25 4.70703 15.42 4.65103 14.35L4.30334 7.75"),
                s("M2.75 4.75H15.25"),
                s("M6.75 4.75V2.75C6.75 2.2 7.198 1.75 7.75 1.75H10.25C10.802 1.75 11.25 2.2 11.25 2.75V4.75"),
            ])
        case .ai: // AiIcon.tsx — small sparkle filled+stroked, large sparkle stroked
            return VectorIcon(elements: [
                VectorElement(
                    geometry: .path("M4.75 10.25L5.35 12.65L7.75 13.25L5.35 13.85L4.75 16.25L4.15 13.85L1.75 13.25L4.15 12.65L4.75 10.25Z"),
                    paint: .fillAndStroke(width: w)
                ),
                s("M11.25 1.75L12.667 5.33301L16.25 6.75L12.667 8.16699L11.25 11.75L9.833 8.16699L6.25 6.75L9.833 5.33301L11.25 1.75Z"),
            ])
        case .images: // ImagesIcon.tsx
            return VectorIcon(elements: [
                s("M4,15.25l5.836-5.836c.781-.781,2.047-.781,2.828,0l3.086,3.086"),
                rect(2.25, 4.75, 13.5, 10.5, rx: 2),
                line(4.75, 1.75, 13.25, 1.75),
                circle(5.75, 8.25, r: 1.25, paint: .fill()),
            ])
        case .camera: // CameraIcon.tsx
            return VectorIcon(elements: [
                s("M14.25,3.75h-2.25l-.507-1.351c-.146-.39-.519-.649-.936-.649h-3.114c-.417,0-.79,.259-.936,.649l-.507,1.351H3.75c-1.105,0-2,.895-2,2v6.5c0,1.105,.895,2,2,2H14.25c1.105,0,2-.895,2-2V5.75c0-1.105-.895-2-2-2Z"),
                circle(9, 9, r: 2.75),
                circle(4.25, 6.25, r: 0.75, paint: .fill()),
            ])
        case .folder: // FolderIcon.tsx
            return VectorIcon(elements: [
                s("M2.25,8.75V4.75c0-1.105,.895-2,2-2h1.951c.607,0,1.18,.275,1.56,.748l.603,.752h5.386c1.105,0,2,.895,2,2v2.844"),
                s("M4.25,6.75H13.75c1.105,0,2,.895,2,2v4.5c0,1.105-.895,2-2,2H4.25c-1.105,0-2-.895-2-2v-4.5c0-1.105,.895-2,2-2Z"),
            ])
        case .copy: // CopyIcon.tsx
            return VectorIcon(elements: [
                s("M2.25 6.75V13.25C2.25 14.355 3.145 15.25 4.25 15.25H11.75"),
                s("M7.25 12.25H13.75C14.8546 12.25 15.75 11.355 15.75 10.25V4.75C15.75 3.645 14.8546 2.75 13.75 2.75H7.25C6.1454 2.75 5.25 3.645 5.25 4.75V10.25C5.25 11.355 6.1454 12.25 7.25 12.25Z"),
            ])
        case .comment: // CommentIcon.tsx
            return VectorIcon(elements: [s(commentBubble)])
        case .draft: // DraftIcon.tsx
            return VectorIcon(elements: [
                s("M5.75 6.75H7.75"),
                s("M5.75 9.75H10.25"),
                s("M15.16 6.25H11.75C11.198 6.25 10.75 5.802 10.75 5.25V1.85201"),
                s("M15.25 8.0405V6.664C15.25 6.3989 15.145 6.144 14.957 5.957L11.043 2.04289C10.855 1.85489 10.601 1.74989 10.336 1.74989H4.75C3.645 1.74989 2.75 2.64589 2.75 3.74989V14.2499C2.75 15.3539 3.645 16.2499 4.75 16.2499H8.1656"),
                s("M13.7959 16.4542L16.9571 13.293C17.3476 12.9025 17.3476 12.2693 16.9571 11.8788L16.3713 11.293C15.9808 10.9025 15.3476 10.9025 14.9571 11.293L11.7959 14.4542L11.0001 17.2501L13.7959 16.4542Z"),
            ])
        case .search: // SearchIcon.tsx
            return VectorIcon(elements: [
                s("M15.75 15.75L11.6386 11.6386"),
                s("M7.75 13.25C10.7875 13.25 13.25 10.7875 13.25 7.75C13.25 4.7125 10.7875 2.25 7.75 2.25C4.7125 2.25 2.25 4.7125 2.25 7.75C2.25 10.7875 4.7125 13.25 7.75 13.25Z"),
            ])
        case .more: // MoreIcon.tsx — three dots, filled and stroked
            return VectorIcon(elements: [
                circle(9, 9, r: 0.5, paint: .fillAndStroke(width: w)),
                circle(3.25, 9, r: 0.5, paint: .fillAndStroke(width: w)),
                circle(14.75, 9, r: 0.5, paint: .fillAndStroke(width: w)),
            ])
        case .gear: // GearIcon.tsx
            return VectorIcon(elements: [
                s("M9 11.2495C10.2426 11.2495 11.25 10.2422 11.25 8.99951C11.25 7.75687 10.2426 6.74951 9 6.74951C7.75736 6.74951 6.75 7.75687 6.75 8.99951C6.75 10.2422 7.75736 11.2495 9 11.2495Z"),
                s("M15.175 7.27802L14.246 6.95001C14.144 6.68901 14.027 6.42999 13.883 6.17999C13.739 5.92999 13.573 5.69999 13.398 5.48099L13.578 4.513C13.703 3.842 13.391 3.164 12.8 2.823L12.449 2.62C11.857 2.278 11.115 2.34699 10.596 2.79099L9.851 3.42801C9.291 3.34201 8.718 3.34201 8.148 3.42801L7.403 2.79001C6.884 2.34601 6.141 2.27699 5.55 2.61899L5.199 2.82199C4.607 3.16299 4.296 3.84099 4.421 4.51199L4.601 5.47699C4.241 5.92599 3.955 6.42299 3.749 6.95099L2.825 7.27701C2.181 7.50401 1.75 8.11299 1.75 8.79599V9.20099C1.75 9.88399 2.181 10.493 2.825 10.72L3.754 11.048C3.856 11.309 3.972 11.567 4.117 11.817C4.262 12.067 4.427 12.297 4.602 12.517L4.421 13.485C4.296 14.156 4.608 14.834 5.199 15.175L5.55 15.378C6.142 15.72 6.884 15.651 7.403 15.207L8.148 14.569C8.707 14.655 9.28 14.655 9.849 14.569L10.595 15.208C11.114 15.652 11.857 15.721 12.448 15.379L12.799 15.176C13.391 14.834 13.702 14.157 13.577 13.486L13.397 12.52C13.756 12.071 14.043 11.575 14.248 11.047L15.173 10.721C15.817 10.494 16.248 9.885 16.248 9.202V8.797C16.248 8.114 15.817 7.50502 15.173 7.27802H15.175Z"),
            ])
        case .refresh: // RefreshIcon.tsx
            return VectorIcon(elements: [
                s("M5.25 9.5L3 7.25L0.75 9.5"),
                s("M13.495 13.345C12.3587 14.5226 10.7641 15.25 9 15.25C5.548 15.25 2.75 12.45 2.75 9C2.75 8.4 2.834 7.83003 2.99 7.28003"),
                s("M12.75 8.5L15 10.75L17.25 8.5"),
                s("M4.50629 4.65564C5.64249 3.48544 7.23658 2.75 8.99998 2.75C12.452 2.75 15.25 5.55 15.25 9C15.25 9.58 15.171 10.14 15.024 10.67"),
            ])
        }
    }

    /// `filled` variants, where the .tsx has one. `nil` means outline-only.
    static func filled(_ icon: NucleoIcon) -> VectorIcon? {
        switch icon {
        case .speaker: // nucleo-ui-fill-18 — IconVolumeUpFill18, verbatim
            return VectorIcon(elements: [
                f("M11.35,1.567c-.4-.219-.889-.203-1.273,.044l-5.295,3.389H2.25c-1.241,0-2.25,1.009-2.25,2.25v3.5c0,1.241,1.009,2.25,2.25,2.25h2.531l5.295,3.389c.205,.131,.439,.198,.675,.198,.206,0,.412-.051,.599-.153,.401-.219,.65-.64,.65-1.097V2.664c0-.457-.249-.877-.65-1.097Z"),
                f("M14.444,7.056c-.293-.293-.769-.293-1.061,0-.293,.293-.293,.768,0,1.061,.236,.236,.366,.55,.366,.884s-.13,.647-.366,.884c-.293,.292-.293,.768,0,1.061,.146,.146,.338,.22,.53,.22s.384-.073,.53-.22c.52-.519,.806-1.209,.806-1.944s-.286-1.425-.806-1.944Z"),
                f("M15.329,5.111c-.293,.293-.293,.768,0,1.061,1.56,1.56,1.56,4.098,0,5.657-.293,.293-.293,.768,0,1.061,.146,.146,.338,.22,.53,.22s.384-.073,.53-.22c1.039-1.039,1.611-2.42,1.611-3.889s-.572-2.851-1.611-3.889c-.293-.293-.768-.293-1.061,0Z"),
            ])
        case .ballotCircle: // nucleo-ui-fill-18 — IconBallotCircleFill18, verbatim
            return VectorIcon(elements: [
                f("M10.5,6h4.75c.414,0,.75-.336,.75-.75s-.336-.75-.75-.75h-4.75c-.414,0-.75,.336-.75,.75s.336,.75,.75,.75Z"),
                f("M15.25,12h-4.75c-.414,0-.75,.336-.75,.75s.336,.75,.75,.75h4.75c.414,0,.75-.336,.75-.75s-.336-.75-.75-.75Z"),
                circle(5, 5, r: 3, paint: .fill()),
                circle(5, 13, r: 3, paint: .fill()),
            ])
        case .menuLines:
            return VectorIcon(elements: [
                f("M15.75,9.75H2.25c-.414,0-.75-.336-.75-.75s.336-.75,.75-.75H15.75c.414,0,.75,.336,.75,.75s-.336,.75-.75,.75Z"),
                f("M15.75,4.5H2.25c-.414,0-.75-.336-.75-.75s.336-.75,.75-.75H15.75c.414,0,.75,.336,.75,.75s-.336,.75-.75,.75Z"),
                f("M15.75,15H2.25c-.414,0-.75-.336-.75-.75s.336-.75,.75-.75H15.75c.414,0,.75,.336,.75,.75s-.336,.75-.75,.75Z"),
            ])
        case .paperclip:
            return VectorIcon(elements: [
                f("M13.75,4.25c-.414,0-.75,.336-.75,.75v6.75c0,2.068-1.682,3.75-3.75,3.75s-3.75-1.682-3.75-3.75V4.75c0-1.241,1.009-2.25,2.25-2.25s2.25,1.009,2.25,2.25v7c0,.414-.336,.75-.75,.75s-.75-.336-.75-.75V5c0-.414-.336-.75-.75-.75s-.75,.336-.75,.75v6.75c0,1.241,1.009,2.25,2.25,2.25s2.25-1.009,2.25-2.25V4.75c0-2.068-1.682-3.75-3.75-3.75s-3.75,1.682-3.75,3.75v7c0,2.895,2.355,5.25,5.25,5.25s5.25-2.355,5.25-5.25V5c0-.414-.336-.75-.75-.75Z"),
            ])
        case .microphone:
            return VectorIcon(elements: [
                f("M9,12c2.206,0,4-1.794,4-4v-3c0-2.206-1.794-4-4-4s-4,1.794-4,4v3c0,2.206,1.794,4,4,4Z"),
                f("M15.25,7.25c-.414,0-.75,.336-.75,.75,0,3.033-2.467,5.5-5.5,5.5s-5.5-2.467-5.5-5.5c0-.414-.336-.75-.75-.75s-.75,.336-.75,.75c0,3.606,2.742,6.583,6.25,6.958v1.292c0,.414,.336,.75,.75,.75s.75-.336,.75-.75v-1.292c3.508-.376,6.25-3.352,6.25-6.958,0-.414-.336-.75-.75-.75Z"),
            ])
        case .arrowUp:
            return VectorIcon(elements: [
                f("M9,16c-.414,0-.75-.336-.75-.75V3c0-.414,.336-.75,.75-.75s.75,.336,.75,.75V15.25c0,.414-.336,.75-.75,.75Z"),
                f("M13.25,7.75c-.192,0-.384-.073-.53-.22l-3.72-3.72-3.72,3.72c-.293,.293-.768,.293-1.061,0s-.293-.768,0-1.061L8.47,2.22c.293-.293,.768-.293,1.061,0l4.25,4.25c.293,.293,.293,.768,0,1.061-.146,.146-.338,.22-.53,.22Z"),
            ])
        case .stop:
            return VectorIcon(elements: [
                rect(2, 2, 14, 14, rx: 2.75, paint: .fill()),
            ])
        case .xmark:
            return VectorIcon(elements: [
                f("M4,14.75c-.192,0-.384-.073-.53-.22-.293-.293-.293-.768,0-1.061L13.47,3.47c.293-.293,.768-.293,1.061,0s.293,.768,0,1.061L4.53,14.53c-.146,.146-.338,.22-.53,.22Z"),
                f("M14,14.75c-.192,0-.384-.073-.53-.22L3.47,4.53c-.293-.293-.293-.768,0-1.061s.768-.293,1.061,0L14.53,13.47c.293,.293,.293,.768,0,1.061-.146,.146-.338,.22-.53,.22Z"),
            ])
        case .done:
            return VectorIcon(elements: [
                f("M6.5,14c-.192,0-.384-.073-.53-.22l-3.75-3.75c-.293-.293-.293-.768,0-1.061s.768-.293,1.061,0l3.22,3.22L14.72,3.97c.293-.293,.768-.293,1.061,0s.293,.768,0,1.061L7.03,13.78c-.146,.146-.338,.22-.53,.22Z"),
            ])
        case .chevronDown:
            return VectorIcon(elements: [
                f("M9,13.5c-.192,0-.384-.073-.53-.22L2.22,7.03c-.293-.293-.293-.768,0-1.061s.768-.293,1.061,0l5.72,5.72,5.72-5.72c.293-.293,.768-.293,1.061,0s.293,.768,0,1.061l-6.25,6.25c-.146,.146-.338,.22-.53,.22Z"),
            ])
        case .chevronLeft:
            return VectorIcon(elements: [
                f("M11.5,16c-.192,0-.384-.073-.53-.22l-6.25-6.25c-.293-.293-.293-.768,0-1.061L10.97,2.22c.293-.293,.768-.293,1.061,0s.293,.768,0,1.061l-5.72,5.72,5.72,5.72c.293,.293,.293,.768,0,1.061-.146,.146-.338,.22-.53,.22Z"),
            ])
        case .chevronRight:
            return VectorIcon(elements: [
                f("M13.28,8.47L7.03,2.22c-.293-.293-.768-.293-1.061,0s-.293,.768,0,1.061l5.72,5.72-5.72,5.72c-.293,.293-.293,.768,0,1.061,.146,.146,.338,.22,.53,.22s.384-.073,.53-.22l6.25-6.25c.293-.293,.293-.768,0-1.061Z"),
            ])
        case .swap: // the filled variant is on a 24-unit box
            return VectorIcon(viewBox: 24, elements: [
                f("M12.7067 2.96C12.316 2.56933 11.6827 2.56933 11.292 2.96L6.62533 7.62667C6.23467 8.01733 6.23467 8.65067 6.62533 9.04133C7.016 9.432 7.64933 9.432 8.04 9.04133L12 5.08133L15.96 9.04133C16.1547 9.236 16.4107 9.33467 16.6667 9.33467C16.9227 9.33467 17.1787 9.23733 17.3733 9.04133C17.764 8.65067 17.764 8.01733 17.3733 7.62667L12.7067 2.96Z"),
                f("M15.96 14.96L12 18.92L8.04 14.96C7.64933 14.5693 7.016 14.5693 6.62533 14.96C6.23467 15.3507 6.23467 15.984 6.62533 16.3747L11.292 21.0413C11.4867 21.236 11.7427 21.3347 11.9987 21.3347C12.2547 21.3347 12.5107 21.2373 12.7053 21.0413L17.372 16.3747C17.7627 15.984 17.7627 15.3507 17.372 14.96C16.9813 14.5693 16.348 14.5693 15.9573 14.96H15.96Z"),
            ])
        case .clock:
            return VectorIcon(elements: [
                f("M9,1C4.589,1,1,4.589,1,9s3.589,8,8,8,8-3.589,8-8S13.411,1,9,1Zm3.867,10.677c-.146,.21-.379,.323-.617,.323-.147,0-.296-.043-.426-.133l-3.25-2.25c-.203-.14-.323-.371-.323-.617V4.75c0-.414,.336-.75,.75-.75s.75,.336,.75,.75v3.857l2.927,2.026c.341,.236,.426,.703,.19,1.043Z"),
            ])
        case .trash:
            return VectorIcon(elements: [
                f("M3.40771 5L3.90253 14.3892C3.97873 15.8531 5.18472 17 6.64862 17H11.3527C12.8166 17 14.0226 15.853 14.0988 14.3896L14.5936 5H3.40771Z"),
                f("M15.25 4H12V2.75C12 1.7852 11.2148 1 10.25 1H7.75C6.7852 1 6 1.7852 6 2.75V4H2.75C2.3359 4 2 4.3359 2 4.75C2 5.1641 2.3359 5.5 2.75 5.5H15.25C15.6641 5.5 16 5.1641 16 4.75C16 4.3359 15.6641 4 15.25 4ZM7.5 2.75C7.5 2.6143 7.6143 2.5 7.75 2.5H10.25C10.3857 2.5 10.5 2.6143 10.5 2.75V4H7.5V2.75Z"),
            ])
        case .ai:
            return VectorIcon(elements: [
                f("M16.525 6.05302L13.245 4.75602L11.947 1.47502C11.72 0.903021 10.779 0.903021 10.552 1.47502L9.25399 4.75602L5.97399 6.05302C5.68799 6.16602 5.49899 6.44302 5.49899 6.75002C5.49899 7.05702 5.68699 7.33402 5.97399 7.44702L9.25399 8.74402L10.552 12.025C10.665 12.311 10.942 12.499 11.249 12.499C11.556 12.499 11.833 12.311 11.946 12.025L13.244 8.74402L16.524 7.44702C16.81 7.33402 16.999 7.05702 16.999 6.75002C16.999 6.44302 16.812 6.16602 16.525 6.05302Z"),
                f("M4.75 9.5C5.09415 9.5 5.39414 9.73422 5.47761 10.0681L5.96847 12.0315L7.9319 12.5224C8.26578 12.6059 8.5 12.9058 8.5 13.25C8.5 13.5942 8.26578 13.8941 7.9319 13.9776L5.96847 14.4685L5.47761 16.4319C5.39414 16.7658 5.09415 17 4.75 17C4.40585 17 4.10586 16.7658 4.02239 16.4319L3.53153 14.4685L1.5681 13.9776C1.23422 13.8941 1 13.5942 1 13.25C1 12.9058 1.23422 12.6059 1.5681 12.5224L3.53153 12.0315L4.02239 10.0681C4.10586 9.73422 4.40585 9.5 4.75 9.5Z", evenOdd: true),
            ])
        case .images:
            return VectorIcon(elements: [
                circle(5.75, 8.25, r: 1.25, paint: .fill()),
                f("M13.194,8.884c-1.038-1.039-2.851-1.039-3.889,0L3.229,14.961c.3,.179,.647,.289,1.021,.289H13.75c1.105,0,2-.896,2-2v-1.811l-2.556-2.556Z"),
                f("M13.25,2.5H4.75c-.414,0-.75-.336-.75-.75s.336-.75,.75-.75H13.25c.414,0,.75,.336,.75,.75s-.336,.75-.75,.75Z"),
                f("M13.75,16H4.25c-1.517,0-2.75-1.233-2.75-2.75V6.75c0-1.517,1.233-2.75,2.75-2.75H13.75c1.517,0,2.75,1.233,2.75,2.75v6.5c0,1.517-1.233,2.75-2.75,2.75ZM4.25,5.5c-.689,0-1.25,.561-1.25,1.25v6.5c0,.689,.561,1.25,1.25,1.25H13.75c.689,0,1.25-.561,1.25-1.25V6.75c0-.689-.561-1.25-1.25-1.25H4.25Z"),
            ])
        case .camera:
            return VectorIcon(elements: [
                f("M14.25,3h-1.73l-.324-.864c-.254-.68-.913-1.136-1.639-1.136h-3.114c-.726,0-1.384,.457-1.638,1.136l-.324,.864h-1.73c-1.517,0-2.75,1.233-2.75,2.75v6.5c0,1.517,1.233,2.75,2.75,2.75H14.25c1.517,0,2.75-1.233,2.75-2.75V5.75c0-1.517-1.233-2.75-2.75-2.75ZM4,7c-.552,0-1-.448-1-1s.448-1,1-1,1,.448,1,1-.448,1-1,1Zm5,5c-1.657,0-3-1.343-3-3s1.343-3,3-3,3,1.343,3,3-1.343,3-3,3Z"),
            ])
        case .folder:
            return VectorIcon(elements: [
                f("M15.75,9.844c-.414,0-.75-.336-.75-.75v-2.844c0-.689-.561-1.25-1.25-1.25h-5.386c-.228,0-.443-.104-.585-.281l-.603-.752c-.238-.297-.594-.467-.975-.467h-1.951c-.689,0-1.25,.561-1.25,1.25v4c0,.414-.336,.75-.75,.75s-.75-.336-.75-.75V4.75c0-1.516,1.233-2.75,2.75-2.75h1.951c.838,0,1.62,.375,2.145,1.029l.378,.471h5.026c1.517,0,2.75,1.234,2.75,2.75v2.844c0,.414-.336,.75-.75,.75Z"),
                rect(1.5, 6, 15, 10, rx: 2.75, paint: .fill()),
            ])
        case .copy:
            return VectorIcon(elements: [
                f("M11.75 14.5H4.25C3.5605 14.5 3 13.9395 3 13.25V6.75C3 6.3359 2.6641 6 2.25 6C1.8359 6 1.5 6.3359 1.5 6.75V13.25C1.5 14.7666 2.7334 16 4.25 16H11.75C12.1641 16 12.5 15.6641 12.5 15.25C12.5 14.8359 12.1641 14.5 11.75 14.5Z"),
                f("M13.75 2H7.25C5.73122 2 4.5 3.23122 4.5 4.75V10.25C4.5 11.7688 5.73122 13 7.25 13H13.75C15.2688 13 16.5 11.7688 16.5 10.25V4.75C16.5 3.23122 15.2688 2 13.75 2Z"),
            ])
        case .comment:
            return VectorIcon(elements: [f(commentBubble)])
        case .draft:
            return VectorIcon(elements: [
                f("M17.3627 11.2217L17.0273 10.8863C16.3671 10.2247 15.2143 10.2252 14.5522 10.8858L11.391 14.0469C11.3104 14.1275 11.2494 14.2251 11.2123 14.3325L10.2914 17.0034C10.1976 17.2749 10.267 17.5757 10.4701 17.7783C10.6132 17.9214 10.8046 17.998 11.0004 17.998C11.0824 17.998 11.165 17.9848 11.245 17.957L13.9159 17.0361C14.0233 16.999 14.121 16.938 14.2015 16.8574L17.3626 13.6963C17.6932 13.3657 17.8753 12.9263 17.8753 12.459C17.8753 11.9912 17.6933 11.5518 17.3627 11.2217Z"),
                f("M8.8736 16.5136C8.81853 16.6732 8.78227 16.8363 8.76417 17H4.75C3.233 17 2 15.767 2 14.25V3.74902C2 2.23202 3.233 0.999023 4.75 0.999023H10.335C10.802 0.999023 11.241 1.18102 11.572 1.51202L15.486 5.42602C15.817 5.75602 15.999 6.19602 15.999 6.66302V8.89668C15.0937 8.84071 14.1676 9.15057 13.4927 9.82397L10.3303 12.9863C10.0889 13.2277 9.90579 13.5205 9.79447 13.8428L8.8736 16.5136ZM5.75 5.99902H7.75C8.164 5.99902 8.5 6.33502 8.5 6.74902C8.5 7.16302 8.164 7.49902 7.75 7.49902H5.75C5.336 7.49902 5 7.16302 5 6.74902C5 6.33502 5.336 5.99902 5.75 5.99902ZM5 9.74902C5 9.33502 5.336 8.99902 5.75 8.99902H10.25C10.664 8.99902 11 9.33502 11 9.74902C11 10.163 10.664 10.499 10.25 10.499H5.75C5.336 10.499 5 10.163 5 9.74902ZM11.501 6.499C10.951 6.499 10.501 6.049 10.501 5.499L10.5 2.578L14.433 6.499H11.501Z", evenOdd: true),
            ])
        case .search:
            return VectorIcon(elements: [
                f("M11.1083 11.1083C11.4012 10.8154 11.876 10.8154 12.1689 11.1083L16.2803 15.2197C16.5732 15.5126 16.5732 15.9874 16.2803 16.2803C15.9874 16.5732 15.5126 16.5732 15.2197 16.2803L11.1083 12.1689C10.8154 11.876 10.8154 11.4012 11.1083 11.1083Z", evenOdd: true),
                f("M1.5 7.75C1.5 4.29829 4.29829 1.5 7.75 1.5C11.2017 1.5 14 4.29829 14 7.75C14 11.2017 11.2017 14 7.75 14C4.29829 14 1.5 11.2017 1.5 7.75ZM7.75 3C5.12671 3 3 5.12671 3 7.75C3 10.3733 5.12671 12.5 7.75 12.5C10.3733 12.5 12.5 10.3733 12.5 7.75C12.5 5.12671 10.3733 3 7.75 3Z", evenOdd: true),
            ])
        case .gear:
            return VectorIcon(elements: [
                f("M15.676,6.934l-.907-.32c-.104-.251-.22-.499-.358-.739-.131-.227-.296-.425-.451-.631l.184-.983c.153-.826-.232-1.664-.96-2.084l-.352-.203c-.728-.42-1.645-.336-2.284,.211l-.729,.624c-.543-.073-1.087-.08-1.623-.01l-.728-.623c-.639-.546-1.557-.632-2.285-.211l-.351,.203c-.728,.419-1.113,1.257-.959,2.084l.174,.933c-.326,.423-.575,.9-.784,1.399l-.939,.331c-.792,.28-1.324,1.033-1.324,1.873v.405c0,.841,.532,1.593,1.324,1.873l.906,.32c.104,.251,.219,.499,.358,.738,.131,.228,.296,.426,.452,.632l-.184,.983c-.153,.826,.232,1.664,.96,2.084l.352,.203c.309,.178,.651,.266,.992,.266,.463,0,.924-.162,1.292-.477l.724-.62c.278,.037,.556,.057,.833,.057,.266,0,.531-.018,.794-.052l.729,.624c.368,.315,.829,.477,1.293,.477,.341,0,.684-.087,.992-.266l.351-.203c.728-.419,1.113-1.257,.959-2.084l-.174-.934c.326-.423,.574-.899,.783-1.397l.94-.332c.792-.28,1.324-1.033,1.324-1.873v-.405c0-.841-.532-1.593-1.324-1.873Zm-6.676,5.066c-1.657,0-3-1.343-3-3s1.343-3,3-3,3,1.343,3,3-1.343,3-3,3Z"),
            ])
        case .composePen, .add, .microphoneSlash, .keyboard, .waveform, .history, .more, .refresh,
             .menuLeft, .chatTask, .pinTack, .pen, .play, .pause, .skipBack, .skipForward, .brain,
             .fileImage, .filePDF, .fileDocument, .fileSpreadsheet, .fileMarkdown, .fileText,
             .fileCode, .filePresentation, .fileArchive, .fileAudio, .fileVideo, .fileGeneric:
            return nil
        }
    }
    // swiftlint:enable function_body_length line_length

    /// `CommentIcon.tsx`'s shared `bubble` path.
    private static let commentBubble =
        "M15.25 8.75c0 3.452-2.798 6.25-6.25 6.25-.97 0-1.888-.221-2.707-.615L2.75 15.25l.868-3.541C3.181 10.847 2.75 9.847 2.75 8.75 2.75 5.298 5.548 2.5 9 2.5s6.25 2.798 6.25 6.25Z"
}
