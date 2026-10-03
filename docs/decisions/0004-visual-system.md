# 0004 Visual system

Status: selected and implemented for the UI phase.
Date: 2026-10-03.

## Context

The approved compact shell needed a concrete visual language. Kenny chose an existing, already-refined set of values over designing a new one: semantic tokens for color, type, and motion, Nucleo icons, a push-reveal sidebar, a single-card composer, and a voice aura.

## Decision

Adopt the values and recipes, and build the behavior natively in SwiftUI:

- `Tokens` holds every color, metric, and motion value with coherent light and dark variants. Nested names that would shadow SwiftUI (`Color`, `Text`) are `Tokens.Palette` and `Tokens.Typography`.
- Icons are Nucleo outline glyphs (18-unit box, 1.5 stroke), with path data copied verbatim and drawn by a small SVG path parser. Filled variants are used only to show state: an active Outputs glyph, the stop button, play and pause, a reply being read aloud.
- Glass is iOS 26 Liquid Glass. App-drawn glass goes through one `glassControl` modifier: untinted regular glass, no drawn shadow, and a thin directional rim. Controls that host a system menu use Apple's glass button style instead (decision 0006).
- Behavior uses native SwiftUI and system components: `Menu`, sheets with detents, context menus with previews, `sensoryFeedback`, `TextField(axis: .vertical)`, Quick Look, PhotoKit, and AVFoundation.
- Every length scales with the device width from one baseline (see "Device scale" in the architecture note).
- The voice aura is drawn with `Canvas`, because the local machine lacks the Metal toolchain.

## Consequences

The app does not invent values, and one token file is the place to change them. The `Canvas` aura may cost more GPU time than a shader; measure on a device and move to a Metal `colorEffect` if needed. The 15-second skip controls in the read-aloud player use system symbols, because Nucleo has no glyph carrying the number.
