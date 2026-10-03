import Foundation

/// Authored onboarding conversations, never represented as recorded model runs.
/// File contents are rendered by the same local writer as live assistant outputs.
struct ExampleConversation: Sendable {
    enum Output: Sendable {
        case document(name: String, format: String, content: String)
        case chart(name: String, labels: [String], values: [Double])
    }

    let id: UUID
    let title: String
    let messages: [Message]
    let output: Output?

    static let catalog: [Self] = [
        .init(
            id: UUID(uuidString: "E8A01000-0000-4000-8000-000000000001")!,
            title: "From meeting notes to a plan",
            messages: [
                Message(role: .user, text: "Here are our launch notes: Morgan shares the design draft Tuesday, Lee checks signup Thursday, and Sam writes the announcement Friday. Can you organize the next steps?"),
                Message(role: .assistant, text: "### Launch checklist\n- **Morgan:** Share the design draft by Tuesday.\n- **Lee:** Check the signup flow by Thursday.\n- **Sam:** Write the launch announcement by Friday."),
                Message(role: .user, text: "Move Lee's deadline to Wednesday. Write a short update I can share."),
                Message(role: .assistant, text: "Our next steps: Morgan will share the design draft Tuesday, Lee will check signup Wednesday, and Sam will write the launch announcement Friday.")
            ], output: nil
        ),
        .init(
            id: UUID(uuidString: "E8A01000-0000-4000-8000-000000000002")!,
            title: "A trip expense tracker",
            messages: [
                Message(role: .user, text: "For a trip, I spent $45 on the train, $18 on lunch, and $12 at the museum. Put that into a simple expense list."),
                Message(role: .assistant, text: "| Expense | Amount |\n| --- | --- |\n| Train | $45 |\n| Lunch | $18 |\n| Museum | $12 |\n\n**Total: $75.**"),
                Message(role: .user, text: "Add $5 for coffee and make a CSV I can open in a spreadsheet."),
                Message(role: .assistant, text: "Added coffee. The trip now totals **$80** across four expenses. Open the CSV below to use it in a spreadsheet.")
            ], output: .document(name: "Trip Expenses", format: "csv", content: "item,amount\nTrain,45\nLunch,18\nMuseum,12\nCoffee,5\n")
        ),
        .init(
            id: UUID(uuidString: "E8A01000-0000-4000-8000-000000000003")!,
            title: "A workshop checklist to share",
            messages: [
                Message(role: .user, text: "Help plan a workshop: test the projector, print handouts, welcome attendees, collect feedback, and send a recap. Organize it by when to do each task."),
                Message(role: .assistant, text: "**Before:** Test the projector and print handouts.\n\n**During:** Welcome attendees and collect feedback.\n\n**After:** Send the recap."),
                Message(role: .user, text: "Include a microphone check before it starts, and turn that into a one-page PDF."),
                Message(role: .assistant, text: "The checklist includes the microphone check under **Before**. Open the PDF below to preview or share it.")
            ], output: .document(name: "Workshop Checklist", format: "pdf", content: "WORKSHOP CHECKLIST\nBEFORE\n[ ] Test the projector\n[ ] Test the microphone\n[ ] Print the handouts\n\nDURING\n[ ] Welcome attendees\n[ ] Collect feedback\n\nAFTER\n[ ] Send a recap")
        ),
        .init(
            id: UUID(uuidString: "E8A01000-0000-4000-8000-000000000004")!,
            title: "See where the budget goes",
            messages: [
                Message(role: .user, text: "Here's an event budget: space $600, food $250, supplies $100, transport $50. How is it split?"),
                Message(role: .assistant, text: "The total is **$1,000**.\n\n- Space: **60%**\n- Food: **25%**\n- Supplies: **10%**\n- Transport: **5%**\n\nSpace is the largest expense."),
                Message(role: .user, text: "Show the dollar amounts as a bar chart I can share."),
                Message(role: .assistant, text: "Here's the budget as a PNG chart. Each bar shows the category and its dollar amount.")
            ], output: .chart(name: "Event Budget (USD)", labels: ["Space", "Food", "Supplies", "Transport"], values: [600, 250, 100, 50])
        )
    ]
}
