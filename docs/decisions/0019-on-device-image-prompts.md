# 0019 — On-device image prompts

Use the iOS 27 Foundation Models Attachment API with SystemLanguageModel.default after checking its vision capability. The same selected image sources and bounded text context reach chat answers and output generation. Pixel data must never be sent to a remote fallback. Keep iOS 26 supported through the existing explicit OCR boundary.

Reuse the bounded preview cache for orientation-corrected pixel inputs while preserving full-size originals on disk. Missing input files and excessive image/context sizes fail visibly. Four images is the input count ceiling, not a promise that every four-image request fits.

A minimal request on the physical phone identified the licensed photo correctly, while tokenCount of the same image prompt failed with an inability to tokenize. Use text/tool token counting plus an image allowance and let generation enforce the exact limit. Do not downgrade the actual request to OCR merely to make token counting pass.

Reference: https://developer.apple.com/videos/play/wwdc2026/237/

The new-runtime regression also exposed a source-answer presentation failure: facts arrived, but a requested table was omitted. Table requests now choose the table schema directly, with app-rendered Markdown and the existing citation checks, rather than letting an optional table field decide the requested format.
