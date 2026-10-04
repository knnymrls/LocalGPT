# Reviewing LocalGPT

LocalGPT is an iPhone prototype of a private assistant: send a message, follow up, and keep the conversation on the device. It also reads selected documents, creates files, and shares one conversation between text and voice.

## Run it

1. Open `PumaWorkspace.xcodeproj` with Xcode 27 or newer. Swift Package Manager resolves the pinned dependencies.
2. Select the `PumaWorkspace` scheme and an Apple Intelligence-capable iPhone, or a compatible Simulator. Enable Apple Intelligence and let its system model finish preparing. Device builds need your signing team.
3. Run normally. No account, API key, backend, or special launch flag is required. The composer explains model availability if setup is incomplete.

Build with Xcode 27. Deployment starts at iOS 26; pixel-based image understanding is runtime-gated to iOS 27 and a vision-capable system model. Speech may download public model assets on first use. Do not use `-preview` or `-uiState` for a live demonstration: those are explicit DEBUG fixtures.

## Try the core first

Start a new chat, rather than relying on the four preloaded conversations.

- Tell it a fictional project name and a release day, then ask a follow-up that changes the day. Check that it uses the new value.
- Type an unsent draft, relaunch, and confirm the draft and history remain. Continue the same conversation.
- Start a separate chat and ask about an unsaved detail. It should not inherit another chat's context.
- Ask for a short PDF checklist or a CSV with a few specified rows. Open the actual file from the reply or Outputs. PNG charts render inline and open full-size when tapped.

The four preloaded chats contain authored fictional exchanges and real locally rendered files. They demonstrate the interface; they are not captured model evaluations. Continuing one uses the real assistant.

## Architecture in one minute

| Layer | Responsibility |
| --- | --- |
| SwiftUI + shared chat store | One conversation, draft, source selection, and reply lifecycle across input modes. |
| Assistant orchestration | Native speaker history, bounded context, local model calls, scoped tools, cancellation, and recovery. |
| Apple Foundation Models | On-device inference; no remote fallback when unavailable. |
| SQLite + private files | Durable history, drafts, sources, output files, and separately stored memories. Revision checks and deletion tombstones reject stale writes. |
| Document and output services | Local PDF/text extraction, image OCR, scoped retrieval, CSV arithmetic, and PDF/CSV/PNG rendering. |
| Speech | Local recognition and system synthesis. Dictation edits the draft; voice mode sends turns in the same chat. |

Private prompts and documents have no application cloud inference path. Workspace files are excluded from device backups. Public speech assets may download before use. System-provided model assets are managed by Apple. See [verification](verification.md) for what has actually been observed; local architecture alone is not a disconnected-network test.

## Deliberate limits

This is a prototype. The local model can misunderstand, omit information, or generate incorrect facts. Recent ordinary-chat context is bounded to four complete exchanges and may shrink further to fit the model. Saved memory is selective and separate from chat history. Image pixels are passed to the on-device model on supported iOS 27 devices; older systems use OCR. Scene descriptions can be incorrect. Generated pictures remain out of scope. There is no web browsing, cloud sync, desktop client, code execution, or full-duplex voice interruption.

Detailed evidence and remaining checks: [verification](verification.md). Full design: [architecture](architecture.md).
