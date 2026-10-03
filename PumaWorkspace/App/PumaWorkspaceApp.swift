import SwiftUI

@main
struct PumaWorkspaceApp: App {
    var body: some Scene { WindowGroup { WorkspaceStartup() } }
}

private struct WorkspaceStartup: View {
    @State private var container: AppContainer?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let container { RootShell(container: container) }
            else if let error {
                ContentUnavailableView {
                    Label("Workspace could not open", systemImage: "externaldrive.badge.exclamationmark")
                } description: { Text(error) } actions: { Button("Try again") { attempt += 1 } }
            } else { ProgressView("Opening workspace") }
        }
        .task(id: attempt) {
            do { container = try await Task.detached { try AppContainer.make() }.value }
            catch { self.error = error.localizedDescription }
        }
    }
}
