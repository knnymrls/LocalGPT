# 0002 Assistant ownership inside the app

Status: selected for the initial project structure.
Date: 2026-10-03.

## Context

The interface needs a clear connection to assistant behavior, storage, and audio. Assistant request logic should remain understandable and changeable without coupling every screen to a model runtime or database package.

## Decision

Use one SwiftUI app target with an Assistant folder for orchestration, context, read-only tools, and validation. Keep shared types and interfaces in Domain. Keep concrete model, speech, database, document, and retrieval adapters in Infrastructure. AppContainer wires implementations into the presentation layer.

ChatSessionStore presents the active conversation and consumes events through AssistantClient. The first UI build uses mock implementations. The folders are reserved in the scaffold; create their real code when integration starts.

## Consequences

The assistant has clear ownership inside the application, and the model runtime can change behind a contract. A single target keeps initial setup small; folder boundaries require discipline. Consider a separate Swift package when a second app target or extension requires the shared core.

This proposal does not select a winning model, finalize a database schema, create a backend, or prove physical-device behavior.
