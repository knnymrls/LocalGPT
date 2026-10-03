# Puma Workspace design

The interface is one conversation with a composer, kept simple and clean. Controls are icons where an icon is clear. Supporting detail lives in sheets, not permanent panels. System components are used wherever one fits ([decision 0006](decisions/0006-system-components.md)).

This document describes the approved interface. Real services now drive normal launches; explicit DEBUG fixtures remain for isolated UI states. See verification.md for observed checks. Nothing has been verified on a physical device.

## Visual system

- **Color.** Neutral backgrounds (#FFFFFF light, #191919 dark) and a near-black or near-white foreground. The drawer sits a step behind the chat: #F8F8F8 light, #111111 dark. There is no accent color in the chat; selection, the text cursor, marks, and highlights use the foreground ink. File types carry the only color: red for PDFs, blue for documents, green for spreadsheets. The voice aura keeps its own color.
- **Type.** The system sans-serif at four sizes: text 16, caption 13, micro 11, and the 24 heading used only for "Puma". Weights are regular for content, medium for titles and labels, semibold for "Puma" and the Chat pill.
- **Icons.** Nucleo outline glyphs at one stroke weight. A filled glyph means a state is on.
- **Glass.** iOS 26 Liquid Glass for every floating control: top bar buttons, the composer, the add surface, sheets' buttons, and the bars under the top bar.
- **Scale.** Everything is designed at the iPhone 17 Pro's width and scales together, type, icons, controls, spacing, and corners, up to 15% on wider phones.

Values live in `DesignSystem/Tokens`. See [decision 0004](decisions/0004-visual-system.md).

## Shell

The chat fills the screen. A top bar and the composer float over it, each with a progressive blur fading the feed out beneath them, so content never shows as a hard band in the safe areas.

Opening the drawer pushes the whole chat surface to the right with rounded corners and a soft shadow; dragging it back, or tapping it, closes the drawer.

## Top bar

- **Left:** the chats button, then the chat's title in medium weight.
- **Right:** one glass capsule with three controls: New chat, Outputs, and a menu. The Outputs glyph is outlined when the chat has no outputs and filled when it has some.
- **Menu** (system): Pin or Unpin, Uploaded files, Find in chat, Delete. Each has an icon. Delete asks for confirmation.

Two bars can appear directly under the top bar:

- **Read aloud player:** play or pause, time read, speed (1x, 1.25x, 1.5x, 2x), back 15 seconds, forward 15 seconds, close.
- **Notice:** a tick and one line, such as "Message copied", for two seconds.

**Find in chat** replaces the top bar with one glass bar: a search glyph, the field, a match count, previous and next chevrons, and close. It grows out from the menu side and shrinks back. The feed scrolls to the matching message and marks every match in yellow.

## Drawer

- "Puma" and a search button share the top bar's row.
- Chats are plain rows in regular weight. Pinned chats get their own "Pinned" section with a medium-weight label; the rest are labelled "Chats" once something is pinned.
- Pressing and holding a row shows a preview of the chat with Pin, Rename, and Delete.
- The bottom row has the "Chat" pill for a new chat on the left and a Memories button on the right, in the same column as search.
- Search opens a full page with a field docked at the bottom; results match chat titles and message text.

## Composer

One glass card. From top to bottom: the chat's sources as a row of square cards, the text field ("Ask anything…"), and a control row with the plus, an "On-device" label, the microphone, and one primary button.

- The primary button is voice when the field is empty, send when there is text, a filled stop square while a reply is running, and a tick while dictating.
- The microphone dictates into the field until the user taps Finish; sentence boundaries and quiet windows do not stop it. Finish flushes remaining audio, and the waveform uses perceptual input levels in a fixed-height row. Voice mode is a continuous spoken conversation with a mute and an exit control and an aura behind the feed. Every completed spoken reply returns to listening. Silence and opening an output leave the call active. Leaving voice keeps the draft and never sends it.
- Source cards scroll sideways. A file card shows its type glyph and name; a photo card shows the image. Each has an X, removing one slides the rest left, and tapping a card opens the file. Open and Remove are separate accessible buttons.
- Suggestions appear above the composer in an empty chat, and hide once there is a source or a draft.
- A small glass chevron sits just above the composer whenever the feed is scrolled away from the latest message, and returns to it.

## Add surface

The plus opens an app-drawn glass menu: Camera, Photos, Files.

- It scales up out of the plus and sits over it. Dragging moves the whole menu loosely and it springs back; a swipe down, or a tap outside, closes it into the plus.
- Photos and Camera stretch that same glass shape from its bottom-left corner into a panel over the composer.
- **Photos:** a three-column grid of recent photos. Ticking photos adds nothing by itself. The pill reads "All Photos" (which opens the system picker) until something is ticked, then becomes a solid "Add 3 photos"; tapping it adds them.
- **Camera:** a live viewfinder with a white shutter inside a glass ring.
- **Files:** the system file browser.
- A back button returns from the panel to the menu.

## Replies

- **Work.** While the assistant does something specific, such as reading a file, each step appears as a line of plain text in the reply's size, the current one shimmering on a time-driven gradient that stays animated across layout changes. When the answer starts they fold into "Worked for 3s", which expands on tap. A plain answer shows only a shimmering "Thinking" and nothing afterwards. Work rows have no icons.
- **Answer.** Markdown drawn as native text: headings, lists, bold and italic, code, quotes, rules, and tables. Text is 16pt on a 21pt line with 8pt between blocks. A table keeps its columns' natural width and scrolls sideways when it is wider than the screen.
- **No generated UI.** A comparison is a Markdown table in the answer, not a card.
- **Documents.** The files a reply worked from are listed at its end as capsule rows: type glyph, name, arrow. A row opens the file.
- **Actions.** Every finished reply ends with exactly three: Copy, Retry, Read aloud. Retry replaces the newest reply; on an older reply it asks the same question again at the end of the chat. A failed reply shows "Reply interrupted." and a retry.

## Files

- Three glyphs cover every type: Page for PDFs, Report for spreadsheets, Page 2 for documents, text, Markdown, and the rest. They are one size wherever a file is named.
- Every file opens in Quick Look in its own sheet, from a composer card, a reply's document row, Uploaded files, or Outputs.

## Sheets

All sheets share one scaffold: a glass close button, a medium-weight title, and grouped cards of 54pt rows.

- **Outputs:** source files used by replies, generated files, then memories saved from this chat.
- **Uploaded files:** every file and photo added to the app. When empty, center the icon and text in the space below the header at either sheet height; populated lists remain top-aligned.
- **Memories:** everything remembered. Tap a row to read it; press and hold for Remove.
- **Saved memory:** opens from the Saved to memory receipt after a real commit. Shows only the saved text in one plain card. No duplicate quote, date, or Edit/Forget button row. Selective long-term extraction saves enduring context or explicit remember requests.

## States

Empty, streaming, stopped, and failed replies; importing, ready, and removed sources; microphone unavailable; and a muted "On-device" label when the model is preparing, needs setup, or is unsupported. Each can be opened directly with a `-uiState` or `-modelState` launch argument in debug builds.

## Integration and remaining verification

Normal launches use local inference, persistence, file extraction, speech adapters, and automatic memory. Inline numbered references and citation chips open the passage sheet. Model unavailability opens an explanation. Failed replies and imports carry specific reasons.

The live camera, haptics, physical audio interruptions, large Dynamic Type, and a complete light/dark accessibility pass remain device/UI verification work. Simulator microphone routing is separate from recorded-audio speech checks. See [verification](verification.md).
