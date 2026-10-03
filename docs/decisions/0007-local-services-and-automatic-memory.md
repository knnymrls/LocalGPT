# 0007 Local services and automatic memory

Date: 2026-10-03. Status: implementation and runtime validation in progress.

Kenny authorized integrating the completed interface, with automatic memory, seamless voice/text continuity, local documents and generated outputs. He explicitly chose strictly on-device processing and deferred AI-generated pictures. iOS 26 or 27 is acceptable; Simulator is the primary available test environment.

## Decisions

- Foundation Models is the conversation model. No cloud inference, PCC, account, remote app backend, or telemetry.
- Use the installed iOS 26.5 SDK now. Direct multimodal image reasoning remains gated on an iOS 27 SDK/runtime; the current build extracts image text with Vision. Do not advertise OCR as general image understanding.
- Apple SpeechAnalyzer is preferred. WhisperKit with a cached multilingual Whisper base model is the local fallback where Apple's recognizer cannot initialize. Initial speech assets need a network download; microphone samples do not leave the app. No remote transcription fallback.
- GRDB/SQLite owns local conversations, drafts, messages, selected source IDs, artifacts, and memories. Imported originals live in Application Support, not disposable caches. The workspace is excluded from OS backups.
- Extract user-provided context automatically after a send, independently of answering. The user need not say “remember.” Save original supporting words rather than an unchecked model paraphrase. Do not infer facts from questions or source documents.
- A receipt means a database insert actually succeeded. It contains a memory ID and opens that exact record, its original quote, date, and edit/forget actions. Deduplicate concurrent inserts in a database transaction. Reconstruct receipts from memory provenance after an interrupted save.
- Dictation edits the shared draft. Voice conversation submits a completed utterance and speaks the answer. Changing input mode never sends the current partial draft or cancels an ongoing reply. Capture pauses during playback to avoid echo.
- Tools are bounded and selected per request. Reading requires selected, ready source IDs. File/chart/diagram tools are unavailable for ordinary conversation and memory requests. R outputs are script files, never code execution.

## Consequences

The iOS 26 implementation can be built and exercised without waiting for a toolchain upgrade. Direct image reasoning still needs separate implementation and verification on iOS 27. Physical-device performance and interrupted-audio behavior need a device pass; Simulator timing is not an iPhone benchmark. Speech assets increase first-use setup time and disk space, so readiness must be visible and assets must be reused.

This supersedes explicit approval before each memory save in earlier PRD/design text. It also supersedes the earlier requirement to wait for iOS 27 before integrating any real services. It does not change the approved visual shell.
