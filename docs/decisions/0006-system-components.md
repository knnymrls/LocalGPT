# 0006 System components, and where the app draws its own

Status: implemented for the UI phase.
Date: 2026-10-03.

## Context

Review of the interface repeatedly came down to one question: use Apple's component, or draw one. Imitations of system behavior did not feel right, and some system components could not be adjusted to fit.

## Decision

Use the system component wherever one exists and fits. Draw one only when the system's cannot do what the design needs, and say why.

- The chat menu (Pin, Uploaded files, Find in chat, Delete) is a system `Menu`. The top-right capsule is one glass shape holding New chat, Outputs, and an empty slot; the menu's button is laid over that slot from outside the glass, in Apple's clear glass button style. It is nearly invisible at rest, gives the system press response, and the menu grows out of it. Other arrangements were tried and rejected: the menu inside a hand-applied `glassEffect` flashed solid black in dark mode as it opened and closed; making the whole capsule the menu's button grew the menu from the capsule's middle; separate glass buttons side by side left a visible waist between them.
- Files open in Quick Look. Photos use PhotoKit for the recent grid and the system picker for "All Photos". The camera uses AVFoundation. Read aloud uses the system speech synthesizer.
- The add menu (Camera, Photos, Files) is drawn by the app. A system menu's row height and insets are fixed and cannot grow into the photo and camera panel. The app-drawn surface scales out of the plus button, follows a drag and springs back, closes with a swipe down, and stretches the same glass shape into the panel.
- Chat rows use the system context menu with a custom preview of the chat.

## Consequences

System components bring their own motion, haptics, and accessibility, and stay current with the OS. They do not scale with the app's device scale and keep Apple's metrics. The app-drawn add surface must be kept feeling right by hand; its drag distances and thresholds are tuned by eye. A faint ring from the clear glass button is visible around the "…" at rest.
