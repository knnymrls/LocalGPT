# Puma Workspace change log

Record completed work and confirmed decisions. Distinguish a scaffold, implemented interface, mock behavior, real services, and device verification.

## 2026-10-03 — Local services integration

- Connected the approved interface to Foundation Models, GRDB persistence, durable files, scoped retrieval, and real artifact rendering. Normal Debug and Release launches use live services.
- Added automatic, quote-grounded user-context memory with atomic deduplication and post-commit Saved to memory receipts. Receipts open the exact record; editing and forgetting affect future memory context.
- Added OCR for images/scanned PDFs, source references with passage sheets, CSV calculations, PDF/CSV/JSON/Markdown/text/R output, and chart/diagram PNGs. Generated content can be selected in later requests.
- Added Apple SpeechAnalyzer and cached local Whisper fallback, plus shared draft/voice handoff and callback cancellation. Moved read-aloud service ownership out of the reply control view.
- Added cache reuse, versioned saves, deletion tombstones, reply recovery/checkpoints, bounded context, and explicit errors. Retry preserves memory receipts. Long Markdown table cells now determine their row height.
- Verified 16 deterministic checks and eight opt-in real-model/recorded-speech checks. Built Release for Simulator. Live microphone, disconnected-network, and physical-device passes remain pending; see verification.md.
- Updated the PRD, design, architecture, setup, decision record 0007, and bundled third-party notices. The prior entries below are historical UI/scaffold state, not the current implementation.

## 2026-10-03

- Rewrote the PRD around the product goal, user flows, functional requirements, phased scope, and acceptance criteria.
- Established product-specific design, architecture, change log, and decision documents.
- Created the project folder structure with reserved UI, shared domain, preview, assistant, local infrastructure, resource, and test areas.
- Generated a Swift 6 / iOS 26 Xcode app project and shared scheme from `project.yml`.
- Verified the scaffold builds for the generic iOS Simulator destination with signing disabled.
- Created the private [Puma-Workspace repository](https://github.com/knnymrls/Puma-Workspace) and pushed the initial scaffold to `main`.
- Added the minimal app entry point and an empty RootShell. The approved conversation interface is the next implementation step.

- Implemented the first native SwiftUI interface in Slashy's visual system (decision 0004): ported tokens, Nucleo vector icons, and glass surfaces; push-reveal chat drawer; overlay top bar; feed with streaming, stopped, failed/retry, copy, and empty suggestions; glass composer with attachment menu, model pill, mic, and send/stop/voice button; voice mode with mute, exit, keyboard handoff, floating transcript, and water/rim aura; attachments, model, evidence, memory proposal, and saved memory sheets; comparison card with citation chips, revision marker, unknowns, and per-chat notes.
- Added Domain models and contracts, `ChatSessionStore`, `VoiceSessionController`, `NavigationState`, and `AppContainer`. Mock assistant, mock speech, fixtures, and in-memory repositories are DEBUG-only in PreviewSupport.
- Build-verified with the generic iOS Simulator command (no new warnings). Simulator-verified by screenshots on iPhone 17 Pro (iOS 26.5) in light and dark using DEBUG `-uiState` launch states, including an end-to-end mock text turn and voice turn. Not device-verified; gestures, animations, and keyboard behavior were not exercised by touch.

The scaffold has no database, model integration, actual audio, document extraction, or retrieval implementation. Native UI work remains the next phase.

### Review pass 1 (2026-10-03)

- Drawer reveal rebuilt around one animated progress value, so open and close animate offset, corner radius, and shadow together. Added drag-to-close and left-edge drag-to-open. Build-verified; motion not yet checked by touch.
- Drawer content simplified: New chat, New memory, a divider, then an unsectioned chat list without row icons.
- The Memory sheet gained a field for writing a new memory above the saved list.
- Glass controls now use native Liquid Glass only: the system glass button style for round buttons, glass effect containers for the top bar and composer, and no hand-painted rim or specular.

### Review pass 2 (2026-10-03)

- Composer rebuilt as one card with one fixed-height control row shared by text, dictation, and voice modes. The primary button crossfades its glyph in place and no longer animates layout, which fixes the button flying off when a long draft is cleared. Checked through the simulator accessibility outline; motion not judged visually.
- Dictation (mock speech): the mic shows a live waveform in the control row while words land in the draft, and the primary button becomes a check to finish. Nothing is sent.
- Voice mode: the card collapses to the control row and the mute and exit circles split off it inside one glass container.
- Top and bottom safe areas use a progressive blur that runs through the status bar and home indicator; the system scroll edge effect is hidden on the feed.
- Glass circles are pinned to their intended sizes (40pt chrome, 48pt voice) using the native interactive glass effect.
- Sheets are native: navigation stack, inline title, system toolbar close button, medium and large detents, system sheet material. The attachment preview is a real navigation push.
- Native menus use plain text rows with system insets.
- Drawer is New chat, a divider, and the chats. Manual memory entry was removed; memories only arrive through assistant proposals. The saved-memories sheet exists but has no entry point for now.
- Composer controls lost their tinted backgrounds; the model control moved to the right of the row beside the mic, in regular weight.
- Chrome, composer, and voice control sizes now follow Slashy's text-size scale (40, 36, and 48pt at default text size, up to 1.3x).
- Fixed bare bands in the top and bottom safe areas: the drawer's corner clip was cutting the chat surface at the safe-area frame, so the edge blurs stopped there. The surface is now masked through the safe areas, and the blur carries a stronger page-colour wash so it does not read as a gray band.
- Control sizes scale by device width instead of text size. iPhone 17 Pro is the 1.0 baseline (40, 36, 48pt); iPhone 17 Pro Max is about 1.09 (44, 39, 53pt).
- Drawer rows use regular weight; the active chat is marked by its fill only.
- The bottom edge blur fades out in voice mode so the aura reaches the bottom of the screen.

### Review pass 3 (2026-10-03)

- One type scale for the whole app (`Typography.swift`): 16pt regular for everything read or tapped, 16pt medium only for surface titles, 13pt regular for secondary lines, 11pt for citation chips. No semibold anywhere. Sheet titles use the same scale instead of the system inline title.
- The composer's model control is the model name alone in medium weight, with no chevron, and opens the model sheet.
- Drawer rows and model names use medium weight.
- Voice mode no longer shows a keyboard icon; tapping the transcript hands off to the keyboard.
- The plus button opens the Attachments sheet directly. The system pop-up menu is gone, since iOS fixes its text size.
- Attachments reworked: tap a row to use or stop using it in the chat, long-press for Preview and Remove, and a second card adds from Camera, Photos, or Files (mock imports). A new source joins the chat when ready. Sample data is the three venue sources only.
- Composer field padding evened out: the text sits 16pt from the card's left, right, and top edges and 20pt above the control glyphs.

### Model decision (2026-10-03)

- Chose Apple's on-device system model on iOS 27 as the one model ([decision 0005](decisions/0005-on-device-system-model.md)). Not integrated: the installed toolchain has no iOS 27 SDK.
- The model sheet is now a status surface for that model with four mock availability states, and the composer shows "On-device". The three placeholder open-weight models were removed from the sample data.

### Outputs and sources (2026-10-03)

- The top-right control now opens Outputs: the comparisons this chat produced (tap one to return to it in the conversation) and the items the assistant was asked to remember, with edit and forget. Its dot shows when the chat has outputs.
- What was the Attachments sheet is now Sources, opened only from the composer's plus.
- The model sheet was removed. The composer shows a plain "On-device" label.
- Sheet headers use the same glass circle and Nucleo glyph as the top bar; the system navigation bar is hidden inside sheets.
- Sidebar button uses Nucleo menu-left and New chat uses Nucleo chat-task, both copied verbatim from nucleo-ui-outline-18.
- Chrome circles (top bar, sheets, jump-to-latest) raised from 40pt with a 20pt glyph to 44pt with a 22pt glyph on the iPhone 17 Pro baseline.
- Outputs uses Nucleo ballot-circle on the top-right control and in the sheet's empty state.
- Drawer restructured: "Puma" title with a search button that filters chats by title and message text, the chat list, and a bottom-left "Chat" pill for a new chat. The top New chat row and divider were removed. Search checked through the accessibility outline.
- Softened the chat surface's shadow over the drawer: opacity 0.06 light and 0.16 dark (was 0.14 and 0.30), radius 16 and 4pt offset (was 24 and 8).
- Drawer header shares the top bar's row, so "Puma", the search button, and the menu button sit on one centre line. The "Chat" pill's bottom edge matches the composer card's. "Puma" and "Chat" are semibold, the only two semibold uses; drawer chat rows are regular.
- Glass controls (chrome circles, composer card, voice circles) gained a fine rim: a hairline edge and a top highlight drawn inside the native glass, so they read as glass on a flat page.
- Glass rim sharpened (defined outer edge, bright top specular with fast falloff, darker bottom line) and a tight shadow added. All glass surfaces, including the drawer's search field, now go through one `glassControl` modifier.
- Glass rim is now top and bottom only: a highlight along the top edge and a shade along the bottom, both fading out at the sides. The even outer line was removed.
- Search is a full-screen page opened from the drawer's search button: a centred prompt, results by chat title and message text with a matching line, and a glass field docked at the bottom with a close button. The drawer's inline search field was removed. Flow checked through the accessibility outline.
- Glass rim made consistent across appearances: the same top and bottom lines at the same strengths, drawn in dark ink on the light page and light ink on the dark page, so both edges show in both modes.
- Glass rebuilt on Slashy's approved chrome recipe: untinted regular glass, no drawn shadow, and Slashy's native rim, a 0.75pt conic gradient with the light from the top-left (graphite contour in light mode, quiet white highlight in dark mode). This replaces the earlier hand-tuned top and bottom lines. Viewed in both appearances on the iPhone 17 Pro Max simulator.
- The plus button opens a native menu with Camera, Photos, and Files, each with its Nucleo icon (mock imports), instead of a sheet. The Sources sheet was removed. A chat's sources show as removable glass chips above the composer, where they replace the empty-chat suggestions. Source preview is gone with the sheet. Flow checked through the accessibility outline.
- Chat rows in the drawer use a native menu with a tap action: tap opens the chat, touch and hold shows Rename and Delete anchored to the row. This replaces the context menu, whose lifted preview spilled over the chat surface.
- Fixed the closed drawer being exposed to VoiceOver after the search page was added.
- Proportional scaling: type and every icon now follow the device-width scale along with the controls, so the iPhone 17 Pro Max is the same design drawn about 9% larger. Drawer rows scale too. Margins and corner radii stay fixed. Viewed on the Pro Max simulator.
- Touch and hold on a chat in the drawer lifts a preview of the end of that conversation, with Pin, Rename, and Delete beneath it, each with a Nucleo icon. Pinned chats sort to the top and show a small pin. This replaces the plain row menu. Viewed on the Pro Max simulator.
- Save is the default action in the rename and edit-memory alerts, so the system draws it as the prominent blue button.
- Menu icons are 24pt, up from 18pt, matching the system's own menu symbols.
- Sources moved back inside the composer as a sideways-dragging row of square cards above the field: photos as square thumbnails (placeholder until real images exist), files with their icon and name, each with an X. Removing one slides the rest left. The glass chips above the composer were removed. Viewed on the Pro Max simulator.
- The plus menu is drawn by the app as a glass panel instead of a system menu, so its glyphs sit the same distance from the left as from the top and bottom, in the normal text colour. iOS fixes a native menu's insets, which sit wider on the left. The plus turns to an X while the menu is open, and a tap elsewhere closes it.
- Proportional scaling done properly: every padding, gap, size, and corner radius now goes through `pt()` on the same device-width scale as type, icons, and controls (about 165 fixed values converted). The iPhone 17 Pro stays the 1.0 baseline and is unchanged; the Pro Max is the same design about 9% larger. Lengths snap to whole pixels. Viewed on the Pro Max simulator. The voice aura's geometry is screen-proportional already and was left as is.
- The Outputs badge dot is drawn inside the glass button, so it is no longer half hidden behind it.
- Photos and Camera open as an in-place panel over the composer (recent-photos grid, live viewfinder); Files opens the system file browser (implemented, build-verified; camera capture is not verified, the simulator has none). Picked items become source cards; the import behind them is still mock and no file content is read. The simulator has no camera, so Camera adds a placeholder photo there.
- Added twelve attachment kinds detected from the file extension, each with its own Nucleo glyph, and type colours from Slashy's badge palette: red PDF, blue document, green spreadsheet, foreground for the rest. Photo cards show a thumbnail of the picked image.
- The photo and camera panel, its All Photos pill, and the shutter are Liquid Glass. Ticking photos turns the pill into a growing count ("Add 3 photos"); tapping it finishes.
- The add menu and the photo and camera panel are one glass surface: it scales out of the plus, then the same shape stretches into the panel. Ticked photos join the chat only on "Add N photos". The plus no longer turns into an X. Recent photos are preloaded and cached. Checked by frame-by-frame recording on the simulator; not device-verified.
- Removed the purple accent from the text cursor, selection, badge dot, comparison marks, and evidence highlight; they use the foreground ink. Only the voice aura keeps its colour.
- The add menu's pressed mark is one rounded container that slides between rows with the finger; the row under it lifts slightly and the menu gives a few points when dragged past its edge.
- The plus now opens the system `Menu` instead of an app-drawn one; the custom surface is only the photo and camera panel. Placeholder reads "Ask anything…".
- Returned to the app-drawn add menu (the system menu's row height and insets cannot be changed). It scales out of the plus, can be dragged and springs back, closes with a swipe down, and stretches into the photo and camera panel. Checked by frame-by-frame recording on the simulator.
- Replies follow Slashy's turn presentation (implemented, mock data, simulator-checked): work steps appear live with a shimmer on the current one and fold into "Worked for Ns"; the answer renders Markdown (headings, lists, bold, code, quotes); the documents it drew on are listed at its end with their type; every finished reply has Copy, Retry, and Read aloud. Read aloud uses the system voice (not heard on a device). The streaming caret is gone.
- Top bar's right side is one glass module: new chat, Outputs, and a system menu (Pin, Uploaded files, Find in chat, Delete). Added the Uploaded files sheet, a file preview sheet opened from a reply's document row, and a find bar. Replies no longer draw a comparison card: comparisons are Markdown tables. Work rows are text only, and steps appear only for specific work such as reading a file. Fixed the feed snapping left when a reply changed height and the jump-to-latest arrow not appearing. Simulator-checked: module, table, arrow, expanding work row, file preview. Not exercised: the menu's items, find bar, Uploaded files list.
- Outputs now lists the files a chat's replies worked from (same rows as Uploaded files); memories are plain one-line rows. File glyphs are Nucleo Page (PDF), Report (spreadsheets), and Page 2 (everything else), one size everywhere. Imported files are copied into the app and open in Quick Look in their own sheet; sample files show their extracted text. Read aloud has a player bar under the top bar (play/pause, time, speed, skip, close). The chat menu has icons; Find in chat is one glass bar with search glyph, previous, next, and close, and no longer morphs. The top-right module uses native interactive glass. Jump-to-latest arrow is smaller. Simulator-checked: Outputs sheet, glyphs, player bar. Not exercised: menu items, find bar, Quick Look with a real file, skip and speed.
- The drawer shows pinned chats in their own "Pinned" section with a medium-weight label, and labels the rest "Chats" once something is pinned (build-verified, not looked at). The sample attachments now have real files behind them (a PDF, a text file, a PNG, a CSV, and a Markdown file, written on first use), so they open in Quick Look; the viewer has a close button. Simulator-checked: the sample PDF opening in Quick Look.
- Find in chat travels to the matching message and marks every match in yellow; the bar grows out of the menu side and back. Find and jump-to-latest use chevrons; the jump chevron sits just above the composer. The Outputs glyph is filled when the chat has outputs (no dot). Fixed the Page glyph: its outer rectangle's rotation had been dropped, so it drew landscape. Text, Markdown, code, and CSV files open in the app's own viewer (formatted text, a table for CSV); other files use Quick Look. Simulator-checked: find travel and highlight, chevron position, Page glyph. Not looked at: find bar animation, filled Outputs glyph, the text viewers.
- Copying a reply shows a "Message copied" glass bar under the top bar for two seconds. Markdown tables keep their columns' natural width and scroll sideways when wider than the screen. The jump-to-latest chevron's at-the-end check was wrong and is fixed, so it hides once the feed is at the latest message. Sample chats now reference the CSV, Markdown, and PNG samples. Simulator-checked: the copied bar, the Uploaded files list with all five samples, no chevron at the end of a chat.
- Every file opens in Quick Look again (the app's own text, Markdown, and CSV viewers are removed). Tapping a file or photo card in the composer opens it. Simulator-checked: the PDF from a composer card, the Markdown sample as plain text. CSV in Quick Look was seen loading but not seen rendered.
- Fixed the top-right module flashing solid black when its menu opened and closed: the capsule's glass is now a layer behind the controls, so the system menu grows from the "…" button alone. Reproduced and confirmed fixed by frame-by-frame recording on the simulator.
- The composer's stop button uses the filled square. Play, pause, and the reply's speaker (while reading) use Nucleo's filled glyphs. Reworked the top-right module again: the buttons are inside the capsule's glass and the menu is laid over its last slot as a sibling, so icons are sharp at rest and the capsule no longer flashes black around the menu (the previous attempt drew the glass over the icons). Checked at rest and by recording the menu.
- Top-right module is three controls in Apple's glass button style joined with glassEffectUnion. The whole capsule now grows into the menu natively with the system press response and no black flash (a hand-applied glassEffect around a Menu flashes black; the system style does not). Read-aloud skips use the system's 15-second symbols. Recorded and checked frame by frame on the simulator.
- The top-right capsule is now the menu's own button in Apple's glass style, drawing all three glyphs, so the system treats the whole capsule as the menu's source. New chat and Outputs are clear tap targets laid over their glyphs. Recorded: capsule lights and the menu grows from it with no black flash; Outputs still opens its sheet.
- Added a Memories button to the drawer's footer, in the same column as the search button, opening a Memories sheet (shared rows with Outputs' Remembered section). The drawer has its own background, slightly darker than the chat in dark mode and barely off white in light mode. Simulator-checked in both appearances.
- Rewrote the design document around what was built, updated the PRD and architecture note where the interface deviated (Markdown comparisons instead of a card, the top-right module and menu, real pickers and Quick Look, read aloud, outputs as files, memories in the drawer), renamed decision 0004 to "Visual system", and added decision 0006 on system components.
- Top-right module settled: one glass capsule with the menu's button laid over its last slot in Apple's clear glass style, so the "…" lights and grows into the menu with no black flash and no seam. Recorded and checked frame by frame on the simulator.
- Top-right module returned to the whole-capsule version at Kenny's request: the capsule is the menu's own system glass button, with New chat and Outputs as tap targets over their glyphs.
