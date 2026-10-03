# 0016 — Validate the core with fresh conversations

Date: 2026-10-03

## Decision

Keep the current feature scope. Prioritize fresh send/reply, corrected follow-ups, isolated chat context, durable history/drafts, and runnable reviewer setup before the recording.

Ordinary conversation uses concise instructions and the system model's native speaker transcript with greedy sampling. Do not duplicate historical user messages into the current prompt or force every conversational reply into a guided object. In live comparisons those approaches caused speaker confusion, invented personal details, and stale corrections. Guided generation remains useful for bounded tools and the single repetition-recovery attempt.

Unrequested copies of a sufficiently long user message enter the same bounded recovery path as repeated assistant replies. Short replies are validated before display. Explicit quote/repeat requests and short greetings are allowed.

## Acceptance and limits

The opt-in live suite now covers changed facts, unknown personal details in a separate chat, topic follow-ups, and a real-model conversation persisted and reloaded through SQLite before continuing. Deterministic checks cover the copy guard and existing lifecycle protections. Review actual response text as well as assertions: keyword checks cannot establish semantic quality.

Preloaded chats are authored UI demonstrations. Reviewer instructions start from an empty conversation. A clean build, a model test, recorded speech, live microphone capture, and disconnected inference are distinct evidence. Record final observed results and outstanding checks in verification.md; do not present fixture content or an offline-looking status bar as proof of local inference.
