# 0003 Project scaffold and product name

Status: scaffold selected; naming superseded by decision 0020.
Date: 2026-10-03.

## Context

Kenny requested a focused PRD, the actual folder structure, and a GitHub repository before beginning the interface implementation.

## Decision

Start with a private repository under Kenny's authenticated personal account. The current public repository, Swift target, and project are named LocalGPT; see decision 0020.

Commit a minimal, buildable SwiftUI scaffold and an XcodeGen specification. The initial UI target uses Swift 6 and iOS 26 with the available Xcode 26.6 toolchain. Reserve feature, shared domain, preview, assistant, infrastructure, resource, and test folders without implementing their services.

Keep the PRD focused on product behavior and acceptance criteria. Maintain design, architecture, change log, and dated decision documents separately.

## Consequences

The repository opens directly in Xcode, and its project can be regenerated consistently. The blank root view is a scaffold; the approved interface remains the next implementation step. The final local model, database, speech assets, and integration toolchain are not selected by this setup.
