import Foundation
import Observation

@MainActor
@Observable
final class NavigationState {
    enum Sheet: Identifiable, Hashable {
        /// What the chat has produced: opened from the top-right control.
        case outputs
        /// Everything remembered, from the drawer.
        case memories
        /// Every uploaded file, from the top bar's menu.
        case files
        /// One file, from a reply's document row.
        case file(UUID)
        case evidence(Citation)
        /// The pending memory proposal ("Remember this?").
        case memoryProposal
        case savedMemory(UUID)

        var id: String {
            switch self {
            case .outputs: "outputs"
            case .memories: "memories"
            case .files: "files"
            case .file(let id): "file-\(id)"
            case .evidence(let c): "evidence-\(c.id)"
            case .memoryProposal: "memoryProposal"
            case .savedMemory(let id): "memory-\(id)"
            }
        }
    }

    /// A message the feed should scroll to (set when an output is picked).
    var scrollTarget: UUID?

    var drawerOpen = false
    /// The composer's plus surface: its menu, and the photo or camera panel
    /// the menu grows into.
    var addMenuOpen = false
    /// The system file browser, from the plus menu's Files.
    var filesPickerOpen = false
    /// The full-screen search page, opened from the drawer.
    var searchOpen = false
    /// Find in chat, in place of the top bar.
    var findOpen = false
    /// What Find in chat is looking for; matches are marked in the feed.
    var findQuery = ""
    /// False once the reader has scrolled away from the newest message.
    var feedAtLatest = true
    /// Bumped to send the feed back to the newest message.
    var jumpToLatest = 0
    var activeSheet: Sheet?

    /// A short confirmation shown under the top bar, such as "Message copied".
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    /// Shows a confirmation for a couple of seconds.
    func show(notice text: String) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func toggleDrawer() { drawerOpen.toggle() }
    func closeDrawer() { drawerOpen = false }
    func openSearch() { searchOpen = true }
    func closeSearch() { searchOpen = false }
    func present(_ sheet: Sheet) { activeSheet = sheet }
    func dismissSheet() { activeSheet = nil }
}
