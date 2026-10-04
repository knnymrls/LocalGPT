# 0018 — Sent inputs and output execution

The physical-device recording exposed two ownership errors: selected context doubled as pending composer attachments, and file execution depended on the model voluntarily calling a tool.

Keep pending input IDs separate from ongoing source context, persist the IDs on the user message, and clear the pending list at send. Preserve the existing selection for follow-ups. Display imported photos only with their user message; assistant inline images are generated outputs.

Resolve explicit output requests before response generation. The model supplies structured document content or chart/diagram data, while the app invokes the validated writer and emits a receipt only after persistence. This extends the verified writer to conversational format corrections and prevents prose-only success. Numeric/source correctness remains subject to evidence checks and local-model limitations.

The build still uses the iOS 26 SDK. A phone running iOS 27 does not make the new image-input API available to an older compiled app. Full photo understanding must be integrated and tested after the Mac toolchain upgrade; OCR is not represented as visual reasoning.

Sent photos use 120-point square previews; output images and composer thumbnails retain their existing presentation. Voice has one floating transcript and an explicit keyboard handoff control. Shared chrome uses regular glass and sheets use their native background, removing forced clear material and a fixed 55% opacity. The attachment menu retains a readability fill. The iOS 27 glass slider still needs an on-device visual comparison; adopting native materials is not itself evidence of every slider position.

Follow-up clarification: use base system glass only. Removed the custom rim, attachment-menu backing, and glass tints, including the tinted voice controls. Use icon color for mute state. The default SwiftUI glass variant is regular; it is not an app-level choice of the user's Tinted preference. No private preference inspection or app-specific transparency control is introduced.
