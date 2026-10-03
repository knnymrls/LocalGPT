# 0014 — Output files are not composer inputs

Date: 2026-10-03

Opening a conversation or previewing a generated file must not select that file in the composer. Keep seeded outputs linked to assistant messages and Outputs, with no default selected source IDs. Upgrade earlier seeded chats once by subtracting only their original output IDs, preserving other selections and user edits. Later intentional selections must survive relaunch.

PNG creation must persist a small preview along with the original file. Use a bounded ImageIO thumbnail for chart and diagram outputs, and repair older generated-image records at startup. File viewing continues to use the full-resolution original through Quick Look.
