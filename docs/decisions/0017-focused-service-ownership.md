# 0017 — Focused service ownership

Date: 2026-10-03

## Decision

Keep the shared chat facade and approved UI, but give stateful workflows explicit owners:

- `ConversationStore`: active-record invariant, selection, revisions, debounced drafts, persistence, receipt restoration, and interrupted replies.
- `AttachmentStore`: attachment presentation and import task lifetimes. Generation identities reject replaced/deleted imports' late results and failures.
- `MemoryCaptureCoordinator`: independent extraction task ownership, replacement, and cancellation through the `MemoryCapture` protocol. No concrete model service appears in chat state.
- `ChatSessionStore`: user actions and reply events joining those stores to one shared conversation for text and voice.
- `LocalAssistantClient`: request lifetime, availability, deadline, cancellation, and error reporting.
- `AssistantTurn`: context, narrow tool registration, response-path selection, and final reference validation.
- `SourceResponder`: evidence gathering and source-backed writing in separate sessions. Verified numerical comparisons retain their direct completion path.

Model catalogs expose their default identifier. Read Aloud is injected through the SwiftUI environment from the composition root; voice receives a stop-reading action. The platform audio service still coordinates the process-wide audio session internally.

Output capability gating remains deterministic and conservative. Explicit revisions may inherit the immediately preceding user request's output type; ordinary conversation cannot inherit output capabilities. Added negation guards and paraphrase coverage. This is not unrestricted semantic intent classification.

## Boundaries retained

No database migration, model-prompt rewrite, or visual redesign accompanies this refactor. Current storage is appropriate for the take-home's bounded history; pagination remains an explicit scalability limit. The refactor localizes that future work in the conversation store/repository. Existing saved files and chats remain compatible.

Use the committed Swift formatter settings for touched orchestration/state files. Formatting is not acceptance: regression checks exercise task replacement, cancellation, drafts, selected sources, real inference, and recorded voice independently.
