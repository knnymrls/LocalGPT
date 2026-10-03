# Puma Workspace

A native iPhone workspace for private conversations, selected documents, and interchangeable voice and text.

**Current stage:** project scaffold and product documentation. The app target builds to an empty root view. The approved conversation interface is the next implementation step; real local AI, audio, document retrieval, and persistence follow after UI review.

## Start here

- [PRD](docs/prd.md): product goal, flows, requirements, scope, and acceptance criteria.
- [Design](docs/design.md): the approved layout and interaction states.
- [Architecture](docs/architecture.md): folder ownership and how services connect.
- [Change log](docs/CHANGELOG.md): completed work and observed implementation status.
- [Decisions](docs/decisions/): the rationale behind major choices.

## Open the project

Open `PumaWorkspace.xcodeproj` in Xcode, select the `PumaWorkspace` scheme, and choose an iPhone simulator. Device builds require your own signing team.

The initial scaffold targets iOS 26 and uses Swift 6, with no third-party dependencies. It was prepared with Xcode 26.6 and the iOS 26.5 SDK. Local inference and speech integration may introduce further device or toolchain requirements later.

The generated project is committed. To regenerate it after adding files or changing targets, use [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate --spec project.yml
```

To validate the scaffold without signing or booting a simulator:

```sh
xcodebuild -project PumaWorkspace.xcodeproj \
  -scheme PumaWorkspace \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## Structure

```text
PumaWorkspace/
├── App/                 App entry, root shell, dependency wiring
├── DesignSystem/        Visual tokens and shared controls
├── Features/            Chat, history, attachments, model picker, voice,
│                        evidence, comparisons, and memory
├── Domain/              Shared types and service contracts
├── PreviewSupport/      Fixtures and mock services for the UI phase
├── Assistant/           Future orchestration, context, tools, validation
├── Infrastructure/      Future local model, speech, storage, documents, search
└── Resources/           Assets, samples, localization
Tests/                   Future meaningful behavior tests
docs/                    PRD, design, architecture, change log, decisions
```

The initial native UI work uses sample data and mock services. Reserved folders indicate ownership, not completed functionality. No database, model runtime, model assets, telemetry, account system, or cloud backend is configured.
