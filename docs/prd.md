# Puma Workspace PRD

Puma Workspace is a native iPhone assistant for private conversations over personal documents. People can type or speak, inspect the evidence behind an answer, create useful files, and carry context into future chats through visible memories.

## Goal

Deliver a polished local-first assistant that demonstrates usable chat, real on-device replies, durable history, and clear architecture. The defining workflow is comparing two venue proposals, changing a requirement, and getting an updated answer with inspectable sources.

The product should feel continuous across voice and text. Its saved state and output receipts must be trustworthy: a “saved” label means a durable write succeeded, and a file link opens a real file.

## Experience

The approved interface remains one chat feed and composer. The top-left control opens the chat drawer with history, search, pinned chats, and Memories. The right module contains New chat, Outputs, and the chat menu. The composer's plus adds files, photos, or camera images. Supporting content opens in sheets.

Typing, dictation, and voice conversation share the active chat, draft, sources, and history. Dictation adds editable text without sending and stays on through pauses until Finish. Finish includes the remaining captured speech. Voice conversation is a continuous foreground session: it sends a completed utterance, speaks the answer, then listens again without another tap. Quiet pauses and inspecting outputs do not end the call. Leaving voice, switching chats, or backgrounding ends capture. Returning to the keyboard keeps partial text and an ongoing reply. Capture pauses during playback; full-duplex interruption is outside this release.

## Requirements

| Area | Behavior |
| --- | --- |
| Chat | Stream real local answers; stop, retry, copy, read aloud; persist history and drafts; recover interrupted replies as stopped. |
| Navigation | Preserve the approved drawer, composer, Outputs, file viewer, search, pin, rename, and delete interactions. |
| Model | One Apple on-device system model. Show preparation, unsupported-device, disabled-model, and failure states truthfully. |
| Inputs | Read selected PDFs, text, Markdown, code, JSON, CSV, and image text. OCR scanned PDF pages and photos. Preserve original files. Unsupported formats give an actionable explanation. |
| Evidence | Only selected, ready sources enter a request. Numbered references open the supporting excerpt and source. Missing facts stay unknown. |
| Revisions | Follow the latest question and changed requirements while keeping conversation context. Comparisons use readable Markdown tables. |
| Memory | Save only stable preferences, enduring personal context, or explicit requests to remember. Most messages save nothing. Temporary task requirements, budgets, guest counts, and one-off plans stay in chat history. Retain supporting words and origin internally, reject questions/guesses/document facts, and deduplicate. |
| Memory receipt | Show **Saved to memory** after commit. Tap to read that exact memory in a simple sheet. Keep removal in a long-press menu on the memory list; no edit/forget detail card. Saved memories also appear in Memories and the originating chat's Outputs. Failed writes never show a saved receipt. |
| Outputs | Create actual PDF, CSV, JSON, Markdown, text, and R files, plus locally rendered chart/diagram PNGs. Preview and share files through system surfaces. No script execution. |
| Voice | Visible preparation/transcript/microphone state; separate dictation and conversation modes; retain draft on handoff; reject callbacks from old sessions; recover from unavailable/interrupted audio. |
| Performance | Cache extraction by content, keep speech assets/model warm, debounce draft writes, checkpoint replies, and avoid document work on the UI actor. |
| Privacy | Process private inputs locally. No cloud fallback, PCC, analytics, or account. Explain initial public-model asset downloads. User data remains in the application sandbox, excluded from backup. |

## Demonstration

1. Import two venue proposals and ask for capacity, price, and accessibility in a table.
2. Open a citation and inspect the original supporting passage.
3. Change the required seated capacity and ask which venue still qualifies. Unspecified accessibility remains unknown.
4. Share a venue preference naturally. Open the resulting memory receipt, then recall the preference in a new chat.
5. Continue with voice, switch to typing, and retain context without losing or accidentally sending the partial draft.
6. Generate a budget CSV or plan PDF and open the actual file in Outputs.
7. Relaunch and recover chats, drafts, files, and memories.

## Acceptance

- A normal launch uses real inference and storage; fixture mode is explicit and DEBUG-only.
- Deletion and cancellation cannot be undone by a late callback or stale save.
- A memory receipt is bound to a committed record and remains inspectable after relaunch; removing it changes future memory context.
- A reviewer can complete the demonstration and see truthful loading/error/recovery states.
- Required assets can be installed once, with subsequent operation verified offline.
- Setup instructions, architecture, measured results, and remaining platform limits are documented separately from product requirements.

## Scope

This build targets iOS 26+ using the installed toolchain. General image reasoning on iOS 27 is a later integration; OCR is the available image input path. AI-generated pictures are deferred. Office documents should be exported to PDF/text/CSV. Audio/video file transcription, web browsing, accounts, cloud sync, unrestricted subagents, external actions, arbitrary code execution, and full-duplex voice are outside this release.

This is a bounded take-home implementation: large-history pagination, extensive multilingual evaluation, physical-device latency/energy measurement, and broad accessibility QA remain release-quality work. Current evidence belongs in [verification](verification.md), not inferred from a successful build.

## Supporting documents

[Design](design.md) · [Architecture](architecture.md) · [Decisions](decisions/) · [Verification](verification.md) · [Change log](CHANGELOG.md)
