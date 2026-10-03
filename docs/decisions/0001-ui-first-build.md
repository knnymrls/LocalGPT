# 0001 UI first with replaceable services

Status: accepted by Kenny.
Date: 2026-10-03, reaffirming the UI-first direction selected October 2.

## Context

The approved conversation layout and voice/text interaction are the immediate priorities. Real database, inference, retrieval, and audio integration would add setup and failure modes before the interface has been reviewed.

## Decision

Build the native SwiftUI screens and transitions first. Use realistic fixtures, mock assistant replies, mock speech events, and in-memory history/attachment records. Define minimal shared contracts so real implementations can replace these services later.

Keep one active conversation state and one editable draft across voice and text. The top area stays minimal, with left chat navigation and right attachment access. Maintain a product-specific PRD, design document, architecture note, change log, and dated decision records.

## Consequences

The UI can be reviewed without provisioning a model or creating a database. Mock streaming, voice, and attachment behavior must remain recognizable as development behavior. Completing the UI does not establish actual offline inference, speech performance, extraction quality, or durable recovery.

After UI review, resolve device/runtime choices and connect the real implementations. The current phase does not include database setup, migrations, indexing, model downloads, or real audio integration.
