# 0005 Apple's on-device system model

Integration update: [decision 0007](0007-local-services-and-automatic-memory.md) permits the iOS 26 local-model baseline and defers direct image reasoning until an iOS 27 toolchain is available.

Status: selected for integration. The interface is implemented against mock availability; no model code exists yet.
Date: 2026-10-03.

## Context

The PRD left the local runtime and default model open. Kenny chose to build on the iOS 27 on-device model, which now accepts images. The product requires that inference and private content stay on the device, with no silent cloud fallback.

Facts below come from Apple's WWDC26 session "What's new in the Foundation Models framework" and secondary write-ups, read on 2026-10-03. They have not been checked against an SDK: this machine has Xcode 26.6 with the iOS 26.5 SDK only. Treat API names and limits as unverified until Xcode 27 is installed.

## Decision

Use Foundation Models `SystemLanguageModel` as the one model.

- It runs on the device, needs no download managed by the app, and ships no weights in the bundle.
- In iOS 27 it reads images: an image is attached to the prompt directly. Screenshots and photos therefore need no separate text extraction before the model can use them. The built-in OCR tool remains available when exact text and a locator are needed for citations.
- It supports tool calling, which the scoped search and read tools need.
- Its context window is small. Apple's session reports 8,192 tokens; one secondary source says 4K. Retrieval must pass bounded excerpts and downscaled images, never whole documents.

Not used:

- `PrivateCloudComputeLanguageModel`. It is the only option with reasoning levels and a 32K window, but it runs on Apple's servers. That conflicts with the on-device requirement, so it stays out unless the product later adds an explicit, visible opt-in.
- Bundled open-weight models through MLX or Core AI. They add a multi-gigabyte download and a memory risk for no clear gain over the system model. `LocalModel` stays a list so one can be added later without changing the interface.

## Interface consequences

- There are no power levels, reasoning levels, or fast mode to expose. Those exist only on the cloud model.
- The composer shows a plain "On-device" label. It is not a button and there is no model sheet: with one model there is nothing to choose.
- The label is muted when the model cannot answer yet. `LocalModel.Availability` mirrors `SystemLanguageModel.availability` (ready, preparing, needs setup, unsupported). How the app explains a non-ready state to the person is still to be designed.
- Launch with `-modelState preparing|needsSetup|unsupported` to see the muted label.

## Consequences

- Integration requires Xcode 27 and raising the deployment target to iOS 27 for image input. Until then the app stays on iOS 26 with mock services.
- Only Apple Intelligence capable iPhones can answer. Others see the unsupported state.
- Answer quality, speed, and the real context limit must be measured on the target device before the comparison flow is declared working.
