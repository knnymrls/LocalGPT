# Puma Workspace PRD

Puma Workspace is a native iPhone assistant for private conversations over your own documents. People can type or speak, choose a local model, inspect the evidence behind an answer, and return to their conversations later.

The first implementation phase is the interface with realistic sample data. Real local inference, audio, retrieval, and persistence follow after the UI has been reviewed.

## Problem and product goal

People often need to compare a few documents, understand their differences, and make a decision. A useful assistant should make that process easy while keeping the material private and making its answers verifiable.

The goal is a small, polished experience: start a conversation, add relevant material, ask by voice or text, inspect a useful answer, and continue without losing context. The prototype must eventually satisfy Puma's core assignment: usable local-first chat, replies, on-device history, and a clear architecture note. [Puma take-home assignment](https://puma.tech/take-home-task/)

## Primary user and use case

The primary user has a small set of personal or work documents and wants help understanding them on their phone. The initial demonstration uses two venue proposals and a screenshot update: compare capacity, price, and accessibility, then revise the comparison when the required guest count changes.

This single workflow demonstrates the product's value without requiring a large collection of unrelated features. Ordinary conversation also works without attachments.

## Product experience

The main screen is a readable conversation with one composer. A left control opens past chats and New chat. A right control opens all workspace attachments. The top area stays minimal. Model selection and voice controls sit beside the composer.

Voice and text are two inputs to the same conversation. They share the draft, history, selected attachments, model, and editable notes. Supporting details appear in focused sheets rather than permanent panels.

## Core user flows

### Start or resume a conversation

Open the chat drawer, start a new chat or choose an existing one, and type a message. Sending shows reply progress and a readable response. The person can stop a reply, recover from a failure, and continue the conversation. Returning to another chat restores its draft and selections.

### Add and inspect context

Open the attachment modal, add a text file, PDF, or screenshot, and select which ready sources the current chat may use. Preview a file before closing the modal. The conversation makes the selected context clear without displaying an extra document deck above the feed.

### Move between voice and typing

Enter voice mode and see the transcript as speech is captured. Return to the keyboard to review or edit it before Send. Existing typed text is retained, and switching input never submits automatically. Replies remain visible and may also be played aloud, with an accessible stop control.

### Inspect and revise an answer

Ask for a comparison. The reply includes a compact comparison card, source references, missing information, and editable user notes. Tapping a reference opens the supporting passage. Changing a requirement produces a revised comparison while preserving the person's notes.

### Choose what carries forward

The assistant can suggest a useful preference to remember. The person previews its wording and workspace scope before saving it, and can later inspect, edit, or forget it. Saving is always explicit.

## Functional requirements

| Area | Required behavior |
| --- | --- |
| Chat | New chat, local history, readable messages, reply progress, stop, failure, and retry. Empty chats provide a clear starting point. |
| Navigation | Left chat drawer and right attachments modal. Each chat retains its draft, selected sources, model, and user notes. |
| Model selection | A compact picker shows the selected model and its availability. Changes apply to future replies; earlier answers retain their model identity. |
| Attachments | Support text, PDF, and screenshot inputs. Show readiness and failures. Only selected, ready sources are available to the assistant. |
| Voice | Shared draft, visible transcript, keyboard handoff, microphone state, optional reply playback, and recovery from unavailable or interrupted audio. |
| Evidence | Source references open the original supporting passage. Unknown, missing, or deleted sources are shown clearly. Unsupported details remain unknown. |
| Comparison | Structured criteria and options, source references, visible revisions, and preserved editable notes. |
| Memory | Preview, explicit save, inspect, edit, and forget within the workspace. |
| Privacy | Inference and private content remain on the device during normal use. No silent cloud fallback. Model acquisition and asset readiness are explained separately. |

## Scope and build order

### Phase 1 Interface

Build the native SwiftUI shell, chat feed and composer, history drawer, attachment modal, model picker, voice presentation, evidence viewer, comparison card, and memory sheet. Use fixtures and mock services to exercise their normal, empty, loading, interrupted, and error states.

This phase establishes the visual and interaction quality. It does not include database setup, model downloads, actual inference, document indexing, or real microphone and speech integration.

### Phase 2 Working local chat

Connect one local model and on-device conversation storage. Complete send, reply, stop, retry, and history recovery. Verify the runnable path and model readiness on the target device before expanding the workflow.

### Phase 3 Complete the demonstrated workflow

Connect selected-document retrieval, source-backed comparisons, voice/text handoff, spoken replies, and explicit memory. Keep the implementation centered on the venue comparison and revision flow.

## Acceptance criteria

The UI phase is ready for integration when:

- The approved shell works across the supported iPhone layouts, light/dark appearance, keyboard states, and larger text sizes.
- Navigation, attachments, and model selection preserve the active chat's draft and edits.
- Voice-to-keyboard handoff produces an editable draft and never sends it automatically.
- The sample comparison can be revised, its original evidence inspected, and its user notes retained.
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

The target physical device, local runtime, default model, and supported speech assets will be selected during integration. Their availability and measured quality determine the final service implementation; they do not block the interface phase.

## Supporting documents

- [Design](design.md): visual rules and interaction states.
- [Architecture](architecture.md): folder ownership and system connections.
- [Change log](CHANGELOG.md): completed work and observed status.
- [Decision records](decisions/): choices, rationale, and consequences.
