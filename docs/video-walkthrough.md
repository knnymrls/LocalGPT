# LocalGPT recording outline

Aim for about two minutes. Use a fresh conversation for the central demonstration. The preloaded chats can show the interface briefly, but do not present their authored responses as live generation.

1. **Open with the product (10 seconds).** “LocalGPT is a native iPhone assistant with on-device inference and locally saved conversations.” Open the drawer briefly, then start a new chat.
2. **Show a real conversation (30 seconds).** Give a fictional project name and a release day. Ask a follow-up changing the day and confirm the answer actually respects that change. Let the real response finish on camera.
3. **Make something useful (30 seconds).** Ask for a small checklist PDF or a bar chart with supplied numbers. Open the resulting file. Images appear directly in the chat.
4. **Show durability (20 seconds).** Leave an unsent draft, close and reopen the app, and show the chat, draft, and file still there.
5. **Explain the architecture (20 seconds).** “SwiftUI owns the interface, a shared store owns the conversation, Apple Foundation Models runs inference, and SQLite plus private files store the workspace. Tools operate only on selected files.”
6. **Close with one tradeoff (10 seconds).** “I focused on iPhone and local privacy. The model and context window are smaller than cloud alternatives; unsupported requests fail visibly rather than falling back to a server.”

Only include voice if you have personally verified the real microphone path on the device being recorded. Dictation and voice conversation are different interactions: dictation edits the draft; voice sends and speaks turns.

For an offline demonstration, first prepare all assets while connected. Then use a physical iPhone in Airplane Mode with Wi-Fi also off, send a genuinely new request, generate an output, and reopen the saved chat. Do not use a Wi-Fi icon overlay or cached transcript as proof of disconnected inference. Record the result honestly; this check remains pending until performed.
