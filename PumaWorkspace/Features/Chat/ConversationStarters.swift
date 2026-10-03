import Foundation

/// Editable examples of supported workflows. These contain input, never fabricated assistant replies.
struct ConversationStarter: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: NucleoIcon
    let prompt: String

    static let examples: [Self] = [
        .init(
            id: "notes", title: "Turn notes into a plan", detail: "Organize sample notes into next steps", icon: .ballotCircle,
            prompt: """
            Rewrite these fictional meeting notes as three short action bullets. Keep each person's name, the task they must do, and their deadline. Do not add headings or nested lists. Do not remember these example details.

            Morgan will share the first design draft on Tuesday. Lee will check the signup flow by Thursday. Sam will write the launch announcement by Friday.
            """
        ),
        .init(
            id: "csv", title: "Build a CSV tracker", detail: "Turn sample expenses into a spreadsheet", icon: .fileSpreadsheet,
            prompt: """
            Create a CSV file named Trip Expenses with exactly two columns: item,amount. Use these fictional sample rows: Train,45 then Lunch,18 then Museum,12. Do not remember these example details.
            """
        ),
        .init(
            id: "pdf", title: "Create a PDF checklist", detail: "Make a file you can open and share", icon: .filePDF,
            prompt: """
            Create a one-page PDF file named Workshop Checklist using this fictional example. Group these tasks into Before, During, and After: test the projector, print the handouts, welcome attendees, collect feedback, and send a recap. Do not remember these example details.
            """
        ),
        .init(
            id: "chart", title: "Make a budget chart", detail: "Visualize sample expenses as a PNG", icon: .ai,
            prompt: """
            Create a bar chart named Sample Budget showing these fictional expenses in dollars: Space 600, Food 250, Supplies 100, Transport 50. Label each category and its amount. Do not remember these example details.
            """
        )
    ]
}
