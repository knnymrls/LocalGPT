# Puma Workspace PRD

Puma Workspace is a native iPhone assistant for private conversations over your own documents. People can type or speak, add their own files and photos, read answers that show which documents they came from, and return to their conversations later.

The first implementation phase is the interface with realistic sample data. Real local inference, audio, retrieval, and persistence follow after the UI has been reviewed.

## Problem and product goal

People often need to compare a few documents, understand their differences, and make a decision. A useful assistant should make that process easy while keeping the material private and making its answers verifiable.

The goal is a small, polished experience: start a conversation, add relevant material, ask by voice or text, inspect a useful answer, and continue without losing context. The prototype must eventually satisfy Puma's core assignment: usable local-first chat, replies, on-device history, and a clear architecture note. [Puma take-home assignment](https://puma.tech/take-home-task/)

## Primary user and use case

The primary user has a small set of personal or work documents and wants help understanding them on their phone. The initial demonstration uses two venue proposals and a screenshot update: compare capacity, price, and accessibility, then revise the comparison when the required guest count changes.

This single workflow demonstrates the product's value without requiring a large collection of unrelated features. Ordinary conversation also works without attachments.

## Product experience

The main screen is a readable conversation with one composer. A left control opens past chats, search, and memories. On the right, one module holds New chat, the chat's outputs, and a menu with Pin, Uploaded files, Find in chat, and Delete. The composer's plus adds sources from the camera, photos, or files, and they appear as cards in the composer. The top area stays minimal. Voice controls and an on-device label sit in the composer.

Voice and text are two inputs to the same conversation. They share the draft, history, selected sources, and model. Supporting details appear in focused sheets rather than permanent panels.

## Core user flows

### Start or resume a conversation

Open the chat drawer, start a new chat or choose an existing one, and type a message. Sending shows reply progress and a readable response. The person can stop a reply, retry it, recover from a failure, copy it, or have it read aloud. Chats can be pinned, renamed, searched, and deleted. Returning to another chat restores its draft and selections.

### Add and inspect context

Tap the plus and take a photo, pick photos, or choose files. What the chat can read appears as cards in the composer; removing a card takes it out of the chat. Any file can be opened from its card, from a reply, or from the list of uploaded files. The conversation makes the selected context clear without an extra document deck above the feed.

### Move between voice and typing

Enter voice mode and see the transcript as speech is captured. Return to the keyboard to review or edit it before Send. Existing typed text is retained, and switching input never submits automatically. Replies remain visible and may also be read aloud, with play, pause, speed, skip, and stop controls.

### Inspect and revise an answer

Ask for a comparison. The reply is written in Markdown: a comparison is a table, with missing information stated plainly, and the documents it worked from are listed at its end and open on tap. Changing a requirement produces a revised table. Source references inside the answer that open the exact supporting passage remain a requirement, and are not yet reachable in the interface.

### Choose what carries forward

The assistant can suggest a useful preference to remember. The person previews its wording before saving it, and can later inspect, edit, or forget it from Memories or the chat's outputs. Saving is always explicit.

## Functional requirements

| Area | Required behavior |
| --- | --- |
| Chat | New chat, local history, Markdown replies, reply progress, stop, failure, retry, copy, and read aloud. Find in chat scrolls to and marks matches. Empty chats provide a clear starting point. |
| Navigation | Left chat drawer with search, pinned chats, and memories. Right module with New chat, Outputs, and a menu (Pin, Uploaded files, Find in chat, Delete). Sources are added from the composer's plus and shown as cards. Each chat retains its draft, selected sources, and model. |
| Model | The composer carries a plain on-device label. There is one model and no picker. Earlier answers retain their model identity. |
| Attachments | Support photos, PDFs, text, Markdown, spreadsheets, and other documents from the camera, photo library, or files. Show readiness and failures. Files open in the system viewer. Only selected, ready sources are available to the assistant. |
| Voice | Shared draft, visible transcript, keyboard handoff, microphone state, optional reply playback, and recovery from unavailable or interrupted audio. |
| Evidence | Source references open the original supporting passage. Unknown, missing, or deleted sources are shown clearly. Unsupported details remain unknown. |
| Comparison | Criteria and options as a Markdown table in the reply, with unknowns stated and the source documents listed. No generated card. |
| Outputs | The files a chat's replies worked from, and what it was asked to remember. |
| Memory | Preview, explicit save, inspect, edit, and forget, from Memories in the drawer or the chat's outputs. |
| Privacy | Inference and private content remain on the device during normal use. No silent cloud fallback. Model acquisition and asset readiness are explained separately. |

## Scope and build order

### Phase 1 Interface

Build the native SwiftUI shell, chat feed and composer, history drawer, add surface with camera, photos, and files, file viewing, voice presentation, Markdown replies, outputs, and memory sheets. Use fixtures and mock services to exercise their normal, empty, loading, interrupted, and error states.

This phase establishes the visual and interaction quality. It does not include database setup, model downloads, actual inference, document indexing, or real microphone and speech integration.

### Phase 2 Working local chat

Connect one local model and on-device conversation storage. Complete send, reply, stop, retry, and history recovery. Verify the runnable path and model readiness on the target device before expanding the workflow.

### Phase 3 Complete the demonstrated workflow

Connect selected-document retrieval, source-backed comparisons, voice/text handoff, spoken replies, and explicit memory. Keep the implementation centered on the venue comparison and revision flow.

## Acceptance criteria

The UI phase is ready for integration when:

- The approved shell works across the supported iPhone layouts, light/dark appearance, keyboard states, and larger text sizes.
- Navigation and attachments preserve the active chat's draft and edits.
- Voice-to-keyboard handoff produces an editable draft and never sends it automatically.
- The sample comparison can be revised, and the documents behind it opened.
- Empty, loading, unavailable, interrupted, and failed states have clear recovery actions.
- Controls support VoiceOver, comfortable touch targets, and reduced motion.

The complete take-home is ready when a reviewer can:

- Run the app, send a message, receive a real local reply, and reopen saved history after relaunch.
- Complete the demonstrated document comparison and revision using both voice and text.
- Inspect supporting passages and see missing evidence accurately represented.
- Stop generation and audio without stale updates changing a newer conversation.
- Verify normal operation with connectivity disabled after required assets are installed.
- Read concise setup instructions, the architecture note, observed device measurements, and known limitations.

## Out of scope

Accounts, cloud sync, cloud inference fallback, external actions, unrestricted agents, web browsing, a share extension, a separate desktop app, and hands-free full duplex conversation are outside the initial prototype. Additional artifact types follow only if the comparison workflow is complete.

## Decisions still needed

The model is decided: Apple's on-device system model on iOS 27, which reads text and images ([decision 0005](decisions/0005-on-device-system-model.md)). The target physical device and supported speech assets will be selected during integration. Their availability and measured quality determine the final service implementation; they do not block the interface phase.

## Supporting documents

- [Design](design.md): visual rules and interaction states.
- [Architecture](architecture.md): folder ownership and system connections.
- [Change log](CHANGELOG.md): completed work and observed status.
- [Decision records](decisions/): choices, rationale, and consequences.
