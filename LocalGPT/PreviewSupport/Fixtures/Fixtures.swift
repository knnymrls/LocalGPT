#if DEBUG
import Foundation

/// Sample records for the UI development configuration.
enum Fixtures {
    // MARK: Sources

    static let harborID = UUID(uuidString: "6A1F0000-0000-4000-8000-000000000001")!
    static let riversideID = UUID(uuidString: "6A1F0000-0000-4000-8000-000000000002")!
    static let guestUpdateID = UUID(uuidString: "6A1F0000-0000-4000-8000-000000000003")!
    static let cateringID = UUID(uuidString: "6A1F0000-0000-4000-8000-000000000004")!
    static let floorPlanID = UUID(uuidString: "6A1F0000-0000-4000-8000-000000000005")!
    static let menuID = UUID(uuidString: "6A1F0000-0000-4000-8000-000000000006")!

    static let harborText = """
    Harbor Hall — Event proposal

    The main hall seats 180 guests at round tables, or 240 standing. The venue fee for a Saturday evening is $6,500, including tables, linens, and a house sound system.

    Accessibility: step-free entrance from the harbor walk, an elevator to the mezzanine, and two accessible restrooms on the main floor.

    Catering is by approved vendors only. Load-in begins at 2 pm.
    """

    static let riversideText = """
    Riverside Loft — Proposal

    Capacity is 120 guests for a seated dinner. Exclusive use on a Saturday evening is $4,200. Rental includes the loft, the terrace, and furniture for up to 120.

    The loft is on the second floor of a converted warehouse. Outside catering is welcome with a $300 kitchen fee.
    """

    static let guestUpdateText = """
    Update from Maya: final guest count is 140, all seated. Please make sure the venue works for wheelchair users — two guests confirmed.
    """

    static let notesID = UUID(uuidString: "6A1F0000-0000-4000-8000-000000000007")!

    static let cateringCSV = """
    Caterer,Per guest,Staff included,Kitchen fee
    Dockside Kitchen,$68,Yes,$0
    Green Table,$74,Yes,$300
    Harvest & Co,$59,No,$300
    """

    static let planningNotes = """
    # Planning notes

    ## Must haves
    - Step-free access
    - Seated dinner for **140**
    - Venue fee under $7,000

    ## Open questions
    1. End time at each venue
    2. Overtime rate
    3. Whether Riverside Loft has an elevator
    """

    /// Each sample has a real file behind it, so it opens in the system viewer.
    static var attachments: [Attachment] {
        [
            Attachment(
                id: harborID, name: "Harbor Hall proposal.pdf", kind: .pdf, readiness: .ready,
                previewText: harborText, fileURL: SampleFiles.harbor?.url
            ),
            Attachment(
                id: riversideID, name: "Riverside Loft proposal.txt", kind: .text, readiness: .ready,
                previewText: riversideText, fileURL: SampleFiles.riverside?.url
            ),
            Attachment(
                id: guestUpdateID, name: "Guest count update.png", kind: .image, readiness: .ready,
                previewText: guestUpdateText, thumbnail: SampleFiles.guestUpdate?.thumbnail,
                fileURL: SampleFiles.guestUpdate?.url
            ),
            Attachment(
                id: cateringID, name: "Catering quotes.csv", kind: .spreadsheet, readiness: .ready,
                previewText: cateringCSV, fileURL: SampleFiles.catering?.url
            ),
            Attachment(
                id: notesID, name: "Planning notes.md", kind: .markdown, readiness: .ready,
                previewText: planningNotes, fileURL: SampleFiles.notes?.url
            ),
        ]
    }

    // MARK: Models

    static let defaultModelID = "apple-on-device"

    /// Apple's on-device system model is the one model. Launch with
    /// `-modelState preparing|needsSetup|unsupported` to review the other
    /// availability states.
    static var models: [LocalModel] {
        let availability: LocalModel.Availability = switch UserDefaults.standard.string(forKey: "modelState") {
        case "preparing": .preparing
        case "needsSetup": .needsSetup
        case "unsupported": .unsupported
        default: .ready
        }
        return [
            LocalModel(
                id: defaultModelID,
                name: "Apple Intelligence",
                shortName: "On-device",
                readsImages: true,
                availability: availability
            ),
        ]
    }

    // MARK: Citations

    static func citation(_ number: Int, _ sourceID: UUID, _ locator: String, _ excerpt: String, span: String) -> Citation {
        let ns = excerpt as NSString
        let r = ns.range(of: span)
        let range = r.location == NSNotFound ? 0..<0 : r.location..<(r.location + r.length)
        return Citation(number: number, sourceID: sourceID, locator: locator, excerpt: excerpt, range: range)
    }

    static let harborCapacityPassage = "The main hall seats 180 guests at round tables, or 240 standing. The venue fee for a Saturday evening is $6,500, including tables, linens, and a house sound system."
    static let harborAccessPassage = "Accessibility: step-free entrance from the harbor walk, an elevator to the mezzanine, and two accessible restrooms on the main floor."
    static let riversidePassage = "Capacity is 120 guests for a seated dinner. Exclusive use on a Saturday evening is $4,200. Rental includes the loft, the terrace, and furniture for up to 120."

    static let options: [Comparison.Option] = [
        .init(id: "harbor", label: "Harbor Hall"),
        .init(id: "riverside", label: "Riverside Loft"),
    ]

    static let criteria: [Comparison.Criterion] = [
        .init(id: "capacity", label: "Capacity"),
        .init(id: "price", label: "Price"),
        .init(id: "accessibility", label: "Accessibility"),
    ]

    /// The comparison as the reply writes it: a Markdown table.
    static let comparisonReply = """
    Here is how the two venues compare.

    | | Harbor Hall | Riverside Loft |
    | --- | --- | --- |
    | **Capacity** | 180 seated | 120 seated |
    | **Price** | $6,500 | $4,200 |
    | **Accessibility** | Step-free, elevator | Not stated |

    Riverside Loft doesn't mention accessibility, so I marked it as not stated.
    """

    static let revisedReply = """
    With **140 seated guests**, the capacity row changes:

    | | Harbor Hall | Riverside Loft |
    | --- | --- | --- |
    | **Capacity** | Fits 140 | Short by 20 |
    | **Price** | $6,500 | $4,200 |
    | **Accessibility** | Step-free, elevator | Not stated |

    Harbor Hall fits comfortably. Riverside Loft is 20 seats short.
    """

    static var comparison: Comparison {
        Comparison(
            title: "Venue comparison",
            criteria: criteria,
            options: options,
            cells: [
                "capacity": [
                    "harbor": .init(value: "180 seated", citations: [citation(1, harborID, "Page 1 · lines 3–4", harborCapacityPassage, span: "seats 180 guests at round tables")]),
                    "riverside": .init(value: "120 seated", citations: [citation(2, riversideID, "Lines 3–4", riversidePassage, span: "Capacity is 120 guests for a seated dinner")]),
                ],
                "price": [
                    "harbor": .init(value: "$6,500", citations: [citation(3, harborID, "Page 1 · lines 4–5", harborCapacityPassage, span: "The venue fee for a Saturday evening is $6,500")]),
                    "riverside": .init(value: "$4,200", citations: [citation(4, riversideID, "Lines 3–4", riversidePassage, span: "Exclusive use on a Saturday evening is $4,200")]),
                ],
                "accessibility": [
                    "harbor": .init(value: "Step-free, elevator", citations: [citation(5, harborID, "Page 2 · lines 14–22", harborAccessPassage, span: "step-free entrance from the harbor walk, an elevator")]),
                    "riverside": .init(value: nil, citations: []),
                ],
            ],
            unknowns: ["Riverside Loft accessibility"],
            revisedCriterionID: nil
        )
    }

    static var revisedComparison: Comparison {
        var c = comparison
        c.title = "Venue comparison"
        c.cells["capacity"] = [
            "harbor": .init(value: "Fits 140", citations: [
                citation(1, harborID, "Page 1 · lines 3–4", harborCapacityPassage, span: "seats 180 guests at round tables"),
                citation(6, guestUpdateID, "Image text region", guestUpdateText, span: "final guest count is 140, all seated"),
            ]),
            "riverside": .init(value: "Short by 20", citations: [
                citation(2, riversideID, "Lines 3–4", riversidePassage, span: "Capacity is 120 guests for a seated dinner"),
                citation(6, guestUpdateID, "Image text region", guestUpdateText, span: "final guest count is 140, all seated"),
            ]),
        ]
        c.revisedCriterionID = "capacity"
        return c
    }

    /// A citation whose source was removed, for the unavailable evidence state.
    static let missingCitation = Citation(number: 7, sourceID: floorPlanID, locator: "Page 3", excerpt: "", range: 0..<0)

    static let memoryProposal = MemoryItem(
        text: "Plan events for 140 seated guests, including two wheelchair users.",
        origin: "From “Guest count update.png” · Today",
        state: .proposed
    )

    static let savedMemories: [MemoryItem] = [
        MemoryItem(text: "Prefer venues within walking distance of the harbor.", origin: "From “Venue shortlist” · Yesterday", state: .saved),
        MemoryItem(text: "Budget ceiling is $7,000 for the venue fee.", origin: "From “Budget notes” · Sep 12", state: .saved),
    ]

    // MARK: Conversations

    static func conversations(now: Date = .now) -> [Conversation] {
        let cal = Calendar.current
        func ago(days: Int, hours: Int = 0) -> Date {
            cal.date(byAdding: .hour, value: -hours, to: cal.date(byAdding: .day, value: -days, to: now)!)!
        }
        return [
            Conversation(
                title: "Venue shortlist",
                createdAt: ago(days: 0, hours: 3), updatedAt: ago(days: 0, hours: 2),
                messages: [
                    Message(role: .user, text: "Which venues are still on the list?"),
                    Message(
                        role: .assistant,
                        text: "Two venues are still on the list:\n\n- **Harbor Hall**\n- **Riverside Loft**\n\nBoth proposals are attached to this chat.",
                        modelID: defaultModelID,
                        steps: ["Reading Harbor Hall proposal.pdf", "Reading Riverside Loft proposal.txt"],
                        workSeconds: 3,
                        documentIDs: [harborID, riversideID]
                    ),
                ],
                selectedSourceIDs: [harborID, riversideID],
                modelID: defaultModelID
            ),
            Conversation(
                title: "Catering questions",
                createdAt: ago(days: 1, hours: 2), updatedAt: ago(days: 1, hours: 1),
                messages: [
                    Message(role: .user, text: "What should I ask the caterer?"),
                    Message(
                        role: .assistant,
                        text: "Going by the quotes, ask each caterer about:\n\n- Dietary options\n- Staffing per guest\n- Setup time\n- Whether the **kitchen fee** is included",
                        modelID: defaultModelID,
                        steps: ["Reading Catering quotes.csv"],
                        workSeconds: 2,
                        documentIDs: [cateringID]
                    ),
                ],
                draft: "Also ask about",
                modelID: defaultModelID
            ),
            Conversation(
                title: "Welcome email draft",
                createdAt: ago(days: 4), updatedAt: ago(days: 4),
                messages: [
                    Message(role: .user, text: "Draft a short welcome note for guests."),
                    Message(role: .assistant, text: "Welcome! We're so glad you're joining us. Doors open at 6 pm, dinner at 7.", modelID: defaultModelID),
                ],
                modelID: defaultModelID
            ),
            Conversation(
                title: "Budget notes",
                createdAt: ago(days: 21), updatedAt: ago(days: 21),
                messages: [
                    Message(role: .user, text: "Keep the venue under $7,000."),
                    Message(
                        role: .assistant,
                        text: "Noted. Both current proposals are under that ceiling, and it matches your planning notes.",
                        modelID: defaultModelID,
                        steps: ["Reading Planning notes.md"],
                        workSeconds: 2,
                        documentIDs: [notesID, guestUpdateID]
                    ),
                ],
                modelID: defaultModelID
            ),
        ]
    }
}
#endif
