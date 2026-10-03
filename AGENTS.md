# Puma Workspace contributor guide

Read `docs/prd.md`, `docs/design.md`, and `docs/architecture.md` before making changes. The current phase integrates real on-device services into the approved native UI. Preserve the approved compact shell and shared voice/text conversation.

## Ownership

- `App`: entry point, shell, navigation, and dependency wiring.
- `DesignSystem`: semantic visual tokens and reusable small controls.
- `Features`: feature screens, components, and presentation state.
- `Domain`: shared data and minimal service/repository contracts.
- `PreviewSupport`: fixtures and explicit mock services.
- `Assistant`: context, memory extraction, orchestration, scoped tools, and validation.
- `Infrastructure`: concrete inference, speech, storage, extraction, rendering, and retrieval.

Use Mintlify's context tool when researching library, framework, SDK, API, or CLI usage. Prefer primary documentation and verify behavior against the installed toolchain.

Keep UI code independent of concrete model and database packages. Use one shared chat state and draft across input modes. Add only contracts needed by the current flow. Production services are the default. Keep mocks behind explicit DEBUG launch arguments. Private input must never enter a remote inference or transcription fallback.

`project.yml` defines the Xcode project. Regenerate the committed project after adding source files. Keep personal Xcode state, build output, credentials, and model weights out of Git.

Maintain `docs/design.md`, `docs/architecture.md`, `docs/CHANGELOG.md`, and dated decision records. Distinguish planned, implemented, mock, build-verified, and device-verified states. Do not report a successful build as proof of working UI or model behavior.

Run checks appropriate to the change. For scaffold or project configuration changes, build the app with the documented generic simulator command. Add meaningful behavior tests when real state transitions or integration contracts warrant them.
