# Puma Workspace design

Status: the compact conversation layout is approved. The native UI implementation follows the committed project scaffold. This document defines that interface in the product's own terms.

## Visual direction

Use a quiet conversation surface with a clear reading hierarchy. Body text uses the system sans-serif; comparison headings and the voice transcript can use the system serif where it supports the accepted preview. Use warm neutral backgrounds, readable text, restrained dividers, and a warm accent for active voice or meaningful changes. Define semantic tokens for surfaces, text, accent, borders, spacing, and motion, with coherent light and dark appearances.

Use glass treatment on controls and navigation. Keep answers and original documents readable against stable surfaces. Shared primitives belong in DesignSystem; message rows, the composer, and comparison cards belong to their features.

## Shell

- Left control opens a drawer containing old chats and New chat.
- Right control opens the attachment modal. It lists all workspace attachments and makes the selected sources for this chat clear.
- Keep the top area minimal. Add no document deck, extra toolbar, status dashboard, or permanent inspector above the conversation. A quiet chat label may remain between the two controls.
- The message feed and composer stay in one shell across keyboard and voice input.
- A compact model pill opens the local model picker. Speaking controls remain distinct from the assistant model choice.

## Conversation and composer

Typed text and accepted transcription share one draft. Entering voice preserves existing text. Provisional speech appears visibly; returning to the keyboard makes it editable before Send. The interface never submits merely because input mode changed.

Voice controls expose microphone state, keyboard handoff, and exit. Audio output has a clear stop control. Opening navigation or a modal pauses capture and retains the draft. Changing chats preserves each chat's draft, selected sources, model, and user notes, and ends active work before changing scope.

Keep the model choice next to the composer in either input mode. Changing it applies to future replies; the existing answer retains its model identity. Make downloaded, unavailable, and setup-needed choices legible without pretending assets are installed.

## Attachments and evidence

The attachment modal lists file names, type/readiness, and whether each source is selected for the current chat. File preview and selection are separate actions. Empty, importing, failed, removed, and ready states have clear next actions.

A citation opens the original excerpt with a page, text range, or image-text region. Returning restores the conversation position and draft. Unknown or deleted sources show an explicit unavailable state. A citation number alone is never sufficient proof of source support.

## Answer surfaces

Use a readable text response and one structured comparison card with criteria, options, citations, unknowns, and editable user notes. A revised comparison marks the changed requirement and result, while retaining user-authored notes. Source facts and user notes stay visibly distinct.

Memory is an explicit sheet: inspect wording, origin, and scope, then save, edit, or forget. Activity is an optional detail view of actual operations and model identity, with sample operations clearly confined to the UI development configuration.

## States to review during the UI build

| Surface | Required sample states |
| --- | --- |
| Chat | Empty, existing history, sample streaming, stopped, interrupted, failed, retry |
| Draft | Typing, voice transcript, editable transcript, preserved per chat |
| Voice | Idle, listening, muted, finalizing, speaking, permission unavailable, interruption |
| Attachments | None, available, selected, importing, failed, removed |
| Model picker | Selected, downloaded, missing assets, unavailable, setup needed |
| Evidence | Original passage, missing source, deleted source |
| Comparison | Initial answer, revised constraint, preserved notes, missing evidence |
| Memory | Proposal, saved, edited, forgotten |

Use meaningful transitions that preserve reading position and editing focus. Respect reduced motion, Dynamic Type, VoiceOver, light/dark appearance, keyboard presentation, and comfortable touch targets. Follow new replies only while the person is reading at the bottom; otherwise expose a jump-to-latest action.

## Current scope

The first native UI pass uses fixtures and simulated assistant, speech, and repository behavior. The goal is to review the real SwiftUI layout and interaction states. Real inference, microphone capture, speech output, database work, model downloads, document extraction, and indexing are later integrations.
