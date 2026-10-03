# 0006 System components, and where the app draws its own

Status: implemented for the UI phase.
Date: 2026-10-03.

## Context

Review of the interface repeatedly came down to one question: use Apple's component, or draw one. Imitations of system behavior did not feel right, and some system components could not be adjusted to fit.

## Decision

Use the system component wherever one exists and fits. Draw one only when the system's cannot do what the design needs, and say why.

- The chat menu (Pin, Uploaded files, Find in chat, Delete) is a system `Menu`. The top-right capsule is that menu's own button in Apple's glass button style, drawing all three glyphs; New chat and Outputs are clear tap targets laid over their glyphs. A hand-applied `glassEffect` around a `Menu` flashed solid black in dark mode as the menu opened and closed; Apple's style does not.
- Files open in Quick Look. Photos use PhotoKit for the recent grid and the system picker for "All Photos". The camera uses AVFoundation. Read aloud uses the system speech synthesizer.
- The add menu (Camera, Photos, Files) is drawn by the app. A system menu's row height and insets are fixed and cannot grow into the photo and camera panel. The app-drawn surface scales out of the plus button, follows a drag and springs back, closes with a swipe down, and stretches the same glass shape into the panel.
- Chat rows use the system context menu with a custom preview of the chat.

## Consequences

System components bring their own motion, haptics, and accessibility, and stay current with the OS. They do not scale with the app's device scale and keep Apple's metrics. The app-drawn add surface must be kept feeling right by hand; its drag distances and thresholds are tuned by eye. With the capsule as one system button, the menu grows from the capsule as a whole, below its middle, and not from the "…" glyph. Variants that grow it from the "…" alone were built and set aside: one left a faint ring around the glyph, one a waist between two pieces of glass.
