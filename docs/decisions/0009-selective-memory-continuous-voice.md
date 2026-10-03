# 0009 Selective memory and continuous voice

Date: 2026-10-03. Status: implemented; validation recorded in verification.md.

Kenny requested less proactive memory, a return to the simple memory presentation, and voice that stays connected across turns like a call. This supersedes broad automatic-context capture and the Edit/Forget detail card in earlier decisions.

## Memory

- Classify only lasting preferences, enduring personal context, and explicit remember requests. Ordinary task constraints, event budgets, guest counts, and temporary plans stay in conversation history.
- Most messages produce no memory. Extraction returns at most two candidates; a separate policy rejects temporary context, opt-outs, and claimed explicit requests with no corresponding user instruction. Verbatim grounding, atomic deduplication, and commit-before-receipt remain required.
- The receipt opens one plain card containing the saved text. Supporting quote, timestamps, and provenance remain stored internally. Remove is available in the memory list's long-press menu; the edit form and detail action row are gone.
- This is conservative model-assisted selection, not a claim of perfect semantic classification. Explicit remember requests may save temporary context intentionally.

## Voice

- The foreground conversation owns a stable audio-session lease across capture, inference, synthesis, and the next listening window. Individual capture/playback IDs continue rejecting stale callbacks.
- Successful playback automatically rearms capture. Empty capture completion rotates the bounded recognizer without sending a message or ending the call. Quiet is not an error.
- Whisper retains only a short silent pre-roll before speech, so a long pause cannot fill the utterance cap. Finalization still runs when the cap is reached.
- Opening Outputs or the drawer does not hang up. Leaving voice, choosing a different conversation, or backgrounding stops audio. Dictation remains separate and never sends automatically.
- Errors and system interruptions stay visible; this change does not add full-duplex speech or background calling.

Tests cover two turns, playback/capture ordering, quiet rollover, long silence before speech, mute, keyboard handoff, and selective memory. Recorded-audio tests use real recognition and synthesis; their input replacement does not establish live microphone quality.
