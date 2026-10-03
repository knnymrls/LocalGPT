# LocalGPT

A native iPhone assistant with local chat, selected-document evidence, selective long-term memory, and shared voice/text conversations. The approved SwiftUI interface connects to real services by default. No account or app backend is required.

## Run

1. Open `PumaWorkspace.xcodeproj` in Xcode 26.6 or newer and select the **PumaWorkspace** scheme.
2. Choose an Apple Intelligence-capable iPhone or compatible Simulator with Apple Intelligence enabled and its model downloaded. Device builds require your signing team. The app explains model unavailability in the composer.
3. Build and run. Allow microphone access when trying voice. Speech assets may download on first use; subsequent recognition is local.

The deployment target is iOS 26. The verified environment is Xcode 26.6 / iOS 26.5 Simulator. iOS 27 direct image understanding is not implemented in this build: images are read with OCR. This Mac's current OS cannot install the current Xcode 27 release without an OS upgrade.

Private inputs are processed locally. Public speech-model assets are the only application-initiated network download. There is no cloud inference fallback, analytics SDK, account, or sync. See [architecture](docs/architecture.md) for boundaries and [verification](docs/verification.md) for observed results and remaining checks.

## Try it

Start with one of the four examples above the empty composer, edit its sample input, then send. See the [demo guide](docs/demo-guide.md) for use cases and follow-up ideas.

- Say or type **“I generally prefer quiet venues.”** After a lasting preference is committed, **Saved to memory** appears below the reply. Tap it to read the memory in a simple sheet. Temporary budgets and guest counts stay in chat history unless you explicitly ask to remember them. Start a new chat and ask about the preference. A long press in Memories provides Remove.
- Add two venue proposals through Files. Compare capacity, cost, and accessibility; tap a numbered reference to inspect its passage. Then change the guest count and ask which venue fits.
- Ask for a PDF checklist, CSV budget, R script, bar chart, or flow diagram. Open the resulting file from the reply or Outputs. R scripts are not executed.
- Dictation fills the editable draft. Voice conversation sends completed utterances and reads replies. Keyboard handoff preserves the partial draft and any in-progress reply.

## Build and check

```sh
xcodebuild -project PumaWorkspace.xcodeproj \
  -scheme PumaWorkspace -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

# Substitute the identifier of your booted simulator.
xcodebuild -project PumaWorkspace.xcodeproj \
  -scheme PumaWorkspace -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO test

# Opt-in checks using the real local model and speech assets.
xcodebuild -project PumaWorkspace.xcodeproj \
  -scheme PumaWorkspaceLiveChecks -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO test
```

The default scheme runs deterministic persistence, import, memory, and interaction tests. Live model checks require available system models; the recorded-audio check may download Whisper assets. Live tests attach responses to the test report and print observed timing. Simulator timing is not an iPhone benchmark.

`project.yml` is the project source of truth; regenerate after adding files:

```sh
xcodegen generate --spec project.yml
```

Swift Package Manager resolves GRDB and WhisperKit with committed pins. Model weights are downloaded outside the repository. DEBUG-only `-preview` / `-uiState` flags select fixtures; a normal Debug or Release launch uses real services.

## Structure

```text
PumaWorkspace/
├── App/                 Startup, dependency wiring, navigation, lifecycle
├── DesignSystem/        Approved visual tokens and controls
├── Features/            Screens and observable presentation state
├── Domain/              Shared records, requests, events, contracts
├── Assistant/           Context, memory extraction, orchestration, tools
├── Infrastructure/      SQLite, files, OCR, renderers, model and speech adapters
├── PreviewSupport/      Explicit DEBUG fixtures
└── Resources/           App assets
Tests/Unit/              Deterministic behavior and local document checks
Tests/Live/              Opt-in real-model and recorded-speech checks
docs/                    Product, design, architecture, decisions, verification
```

- [PRD](docs/prd.md)
- [Design](docs/design.md)
- [Architecture](docs/architecture.md)
- [Verification and limits](docs/verification.md)
- [Change log](docs/CHANGELOG.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
