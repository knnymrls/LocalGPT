import SwiftUI

/// The canvas edge indicates who is speaking.
///
/// USER: a water field rising from the bottom, a sum of four travelling sines
/// whose height, crest depth, and wavelength follow voice energy.
/// ASSISTANT: an accent rim pinned to the left, right, and bottom edges.
/// Speaker changes hand off over 320ms: the outgoing field drains down 7% of
/// the height while the incoming one arrives as a brief accent flood that
/// contracts to the rim.
///
/// This implementation has no Metal toolchain requirement: the per-column
/// height function is drawn in a `Canvas` as
/// thin vertical gradient strips, so alpha is still a continuous function of
/// depth below the surface.
struct VoiceAura: View {
    @Environment(VoiceSessionController.self) private var voice
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var epoch = Date()
    @State private var handoff = Handoff(mix: 0)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if reduceMotion {
                staticAura(size: size)
            } else {
                TimelineView(.animation) { timeline in
                    frame(at: timeline.date, size: size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { handoff = Handoff(mix: voice.speaker == .assistant ? 1 : 0) }
        .onChange(of: voice.speaker) { _, speaker in
            handoff.begin(to: speaker == .assistant ? 1 : 0, at: .now)
        }
    }

    // MARK: Frame

    private var isDark: Bool { colorScheme == .dark }
    private var userColor: Color { isDark ? .white : .black }
    private var userPeak: Double { isDark ? AuraSpec.userPeakDark : AuraSpec.userPeakLight }
    private var assistantPeak: Double { isDark ? AuraSpec.assistantPeakDark : AuraSpec.assistantPeakLight }
    private var gamma: Double { isDark ? AuraSpec.floodGammaDark : AuraSpec.floodGammaLight }

    @ViewBuilder
    private func frame(at date: Date, size: CGSize) -> some View {
        let time = date.timeIntervalSince(epoch)
        // The controller smooths (attack .06 / release .28); the idle floor lives here.
        let level = min(max(voice.energy, 0), 1)
        let energy = AuraSpec.idle + (1 - AuraSpec.idle) * level
        let mix = handoff.mix(at: date)
        let spread = handoff.spread(at: date)
        let side = handoff.spreadSide
        let height = size.height

        let userWeight = 1 - mix
        let drive = min(1, energy + spread * (1 - side) * AuraSpec.arrivalGain)
        let userOpacity = userWeight * pow(drive, AuraSpec.opacityGamma)
        let arrivalOpacity = spread * side
        let rimOpacity = mix * pow(energy, AuraSpec.opacityGamma)
        let rimScale = AuraSpec.rimScaleFloor + (1 - AuraSpec.rimScaleFloor) * energy

        ZStack {
            if userOpacity > 0.001 {
                WaterField(time: time, energy: energy, color: userColor, peak: userPeak, gamma: gamma)
                    .opacity(userOpacity)
                    .offset(y: (1 - userWeight) * AuraSpec.drain * height)
            }
            if arrivalOpacity > 0.001 {
                WaterField(
                    time: time, energy: energy, color: Tokens.accent,
                    peak: assistantPeak * AuraSpec.arrivalShare, gamma: gamma
                )
                .opacity(arrivalOpacity)
            }
            if rimOpacity > 0.001 {
                RimField(size: size, peak: assistantPeak, isDark: isDark)
                    .scaleEffect(x: 1, y: rimScale, anchor: .bottom)
                    .offset(y: (1 - mix) * AuraSpec.drain * height)
                    .opacity(rimOpacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Reduce Motion: a still gradient for the person, a still rim for the agent.
    @ViewBuilder
    private func staticAura(size: CGSize) -> some View {
        switch voice.speaker {
        case .user:
            LinearGradient(
                colors: [userColor.opacity(0), userColor.opacity(userPeak * 0.6)],
                startPoint: UnitPoint(x: 0.5, y: 0.7),
                endPoint: .bottom
            )
        case .assistant:
            RimField(size: size, peak: assistantPeak, isDark: isDark)
                .opacity(pow(AuraSpec.idle, AuraSpec.opacityGamma))
        }
    }
}

// MARK: - Spec

/// Shared motion, energy, and geometry values for the voice aura.
private enum AuraSpec {
    static let idle = 0.5
    static let opacityGamma = 0.7
    static let rimScaleFloor = 0.62
    static let handoff: TimeInterval = 0.32
    static let drain = 0.07
    static let spreadRise: TimeInterval = 0.11
    static let spreadFall: TimeInterval = 0.56
    static let arrivalShare = 0.55
    static let arrivalGain = 0.34

    static let userPeakLight = 0.44
    static let userPeakDark = 0.34
    static let assistantPeakLight = 1.0
    static let assistantPeakDark = 0.84
    static let floodGammaLight = 0.7
    static let floodGammaDark = 1.25

    // Water surface.
    static let baseCalm = 0.90
    static let baseLoud = 0.66
    static let ampCalm = 0.020
    static let ampLoud = 0.058
    static let tighten = 1.5
    static let feather: CGFloat = 330

    // Rim.
    static let rimWidth: CGFloat = 116
    static let rimStops: [Double] = [0, 0.015, 0.029, 0.058, 0.086, 0.129, 0.172, 0.259, 0.345, 0.517, 1]
    static let rimAlphaDark: [Double] = [1, 0.97, 0.77, 0.56, 0.41, 0.29, 0.2, 0.11, 0.065, 0.026, 0]
    static let rimAlphaLight: [Double] = [1, 1, 0.94, 0.82, 0.71, 0.6, 0.5, 0.35, 0.23, 0.1, 0]
    static let rimMaskStops: [Double] = [0, 0.2, 0.31, 0.375, 0.44, 0.5, 0.56, 0.62, 0.69, 0.75, 1]
    static let rimMaskAlpha: [Double] = [0, 0.11, 0.32, 0.54, 0.86, 1, 0.91, 0.72, 0.55, 0.46, 0.47]
    static let rimBand: CGFloat = 0.5
    static let floorHeight: CGFloat = 0.16
    static let floorStops: [Double] = [0, 0.5, 0.74, 0.88, 1]
    static let floorAlpha: [Double] = [0, 0.08, 0.26, 0.6, 1]
    static let floorShareDark = 0.52
    static let floorShareLight = 0.78
    static let cornerRX: CGFloat = 0.3
    static let cornerRY: CGFloat = 0.15
    static let cornerPeak = 0.62

    static func stops(_ color: Color, _ locations: [Double], _ alphas: [Double], peak: Double) -> [Gradient.Stop] {
        zip(locations, alphas).map { .init(color: color.opacity($1 * peak), location: $0) }
    }
}

// MARK: - Handoff

/// Time-based speaker handoff: `mix` 0 = person, 1 = agent, eased in-out quad
/// over 320ms, plus the arrival flood (rise 110ms out-quad, fall 560ms out-cubic).
private struct Handoff {
    var from: Double
    var to: Double
    var start: Date = .distantPast
    var spreadStart: Date = .distantPast
    var spreadSide: Double

    init(mix: Double) {
        from = mix
        to = mix
        spreadSide = mix
    }

    mutating func begin(to target: Double, at date: Date) {
        guard target != to else { return }
        from = mix(at: date)
        to = target
        start = date
        spreadStart = date
        spreadSide = target
    }

    func mix(at date: Date) -> Double {
        let p = min(max(date.timeIntervalSince(start) / AuraSpec.handoff, 0), 1)
        let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        return from + (to - from) * eased
    }

    func spread(at date: Date) -> Double {
        let t = date.timeIntervalSince(spreadStart)
        if t < 0 { return 0 }
        if t < AuraSpec.spreadRise {
            let p = t / AuraSpec.spreadRise
            return 1 - (1 - p) * (1 - p)
        }
        let p = min((t - AuraSpec.spreadRise) / AuraSpec.spreadFall, 1)
        return 1 - (1 - pow(1 - p, 3))
    }
}

// MARK: - Water

/// The person's field: per column, the surface height is a sum of four
/// same-direction sines; below it, alpha ramps over a 330pt feather through
/// smoothstep then the scheme's gamma.
private struct WaterField: View {
    let time: Double
    let energy: Double
    let color: Color
    let peak: Double
    let gamma: Double

    private static let column: CGFloat = 3

    var body: some View {
        let ramp = Gradient(stops: (0...12).map { i in
            let t = Double(i) / 12
            let s = t * t * (3 - 2 * t)
            return .init(color: color.opacity(pow(s, gamma) * peak), location: t)
        })
        Canvas { context, size in
            let w = size.width, h = size.height
            guard w > 0, h > 0 else { return }
            let e = energy
            let base = AuraSpec.baseCalm + (AuraSpec.baseLoud - AuraSpec.baseCalm) * e
            let amp = AuraSpec.ampCalm + (AuraSpec.ampLoud - AuraSpec.ampCalm) * e
            let k = 1 + (AuraSpec.tighten - 1) * e
            let tau = 2 * Double.pi
            let t = time
            var x: CGFloat = 0
            while x < w {
                let u = Double((x + Self.column / 2) / w)
                var wave = 0.70 * sin(tau * (0.72 * k * u + 0.125 * t))
                wave += 0.18 * sin(tau * (1.63 * k * u + 0.188 * t + 0.37))
                wave += 0.08 * sin(tau * (2.71 * k * u + 0.243 * t + 0.71))
                wave += 0.04 * sin(tau * (4.13 * k * u + 0.299 * t + 0.19))
                let surface = CGFloat(base + amp * wave) * h
                let rect = CGRect(x: x, y: surface, width: Self.column, height: max(0, h - surface))
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        ramp,
                        startPoint: CGPoint(x: x, y: surface),
                        endPoint: CGPoint(x: x, y: surface + AuraSpec.feather)
                    ),
                    // Abutting, pixel-aligned columns: no overlap, no AA seams.
                    style: FillStyle(antialiased: false)
                )
                x += Self.column
            }
        }
    }
}

// MARK: - Rim

/// The agent's resting shape: side ramps masked to the bottom half, a floor
/// band across the bottom 16%, and two elliptical corner lights.
private struct RimField: View {
    let size: CGSize
    let peak: Double
    let isDark: Bool

    var body: some View {
        let w = size.width, h = size.height
        let accent = Tokens.accent
        let alphas = isDark ? AuraSpec.rimAlphaDark : AuraSpec.rimAlphaLight
        let edge = AuraSpec.stops(accent, AuraSpec.rimStops, alphas, peak: peak)
        let floorShare = isDark ? AuraSpec.floorShareDark : AuraSpec.floorShareLight
        let corner = AuraSpec.stops(accent, AuraSpec.rimStops, alphas, peak: peak * AuraSpec.cornerPeak)
        let rx = AuraSpec.cornerRX * w, ry = AuraSpec.cornerRY * h

        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                LinearGradient(stops: edge, startPoint: .leading, endPoint: .trailing)
                    .frame(width: AuraSpec.rimWidth)
                Spacer(minLength: 0)
                LinearGradient(stops: edge, startPoint: .trailing, endPoint: .leading)
                    .frame(width: AuraSpec.rimWidth)
            }
            .frame(width: w, height: h * AuraSpec.rimBand)
            .mask(
                LinearGradient(
                    stops: AuraSpec.stops(.black, AuraSpec.rimMaskStops, AuraSpec.rimMaskAlpha, peak: 1),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LinearGradient(
                stops: AuraSpec.stops(accent, AuraSpec.floorStops, AuraSpec.floorAlpha, peak: peak * floorShare),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: w, height: h * AuraSpec.floorHeight)

            ZStack {
                ForEach([CGFloat(0), w], id: \.self) { cx in
                    EllipticalGradient(stops: corner, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: rx * 2, height: ry * 2)
                        .position(x: cx, y: h)
                }
            }
            .frame(width: w, height: h)
        }
        .frame(width: w, height: h, alignment: .bottom)
    }
}
