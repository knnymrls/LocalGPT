# LocalGPT preloaded conversations

Four complete chats appear in regular sidebar history. They contain authored fictional exchanges, not recorded AI runs. The CSV, PDF, and PNG attachments are real files rendered locally. No special labels or section appear in the product, per the requested presentation. Opening them requires no model or download; continuing them uses the live assistant. Seeding does not save personal memories.

| Chat | What to explore | Follow-up to try |
| --- | --- | --- |
| From meeting notes to a plan | A checklist followed by a deadline change and shareable update. | “Move Sam's deadline to Monday.” |
| A trip expense tracker | Four expenses totaling $80, with an openable CSV. | “Create a new CSV with a $20 dinner row.” |
| A workshop checklist to share | Tasks grouped by timing, then a PDF with a microphone check. | “Add a reminder to send invitations and make a new PDF.” |
| See where the budget goes | A $1,000 category breakdown and an openable PNG chart. | “Make a new chart with Food increased to $300.” |

Suggested follow-ups are ideas, not verified guarantees. Chats can be renamed, pinned, continued, and deleted normally. Deletion persists across launches. Existing conversations are preserved. See verification.md for observed checks.

## Other useful demonstrations

| Use case | Input and result | Capability to emphasize |
| --- | --- | --- |
| Meeting follow-through | Paste notes, get action items, export a handoff PDF. | Organizing supplied information and producing a useful file. |
| Venue or vendor selection | Attach two proposals, compare details, inspect supporting excerpts. | Selected-document scope, citations, and explicit unknowns. |
| Receipt or screenshot reading | Attach an image with clear text, ask for the visible amounts or tasks. | Local OCR. Current image handling does not understand arbitrary scenes. |
| Expense analysis | Attach a CSV, request totals by column, then generate a chart. | Deterministic CSV calculations and visual output. |
| Personal preferences | Explicitly remember a lasting preference; inspect its receipt and ask in a new chat. | Visible, durable memory. Sample starters never add fictional preferences. |
| Voice continuation | Begin a task by typing, then continue the same conversation in voice. | Shared context and draft. Live microphone acceptance remains separate from recorded-audio checks. |
| Code or structured exports | Request an R script, JSON, Markdown, or CSV file. | Actual exportable files; scripts are not executed. |

Lead with the PDF and chart: they give a reviewer something concrete to open. Use document evidence and memory as the deeper demonstrations. The current model's broad conversation quality remains under evaluation.

## Images and iOS 27

Apple's iOS 27 system model adds on-device image understanding; a third-party model is not required for that capability. LocalGPT's current iOS 26 build uses text extraction from images instead. Vision prompting remains an integration task for the newer SDK/runtime. [Apple Foundation Models update](https://developer.apple.com/videos/play/wwdc2026/241/)

Picture generation is separate. The new Image Playground model runs on Private Cloud Compute, and Apple has discontinued the programmatic on-device `ImageCreator` API in iOS 27. LocalGPT's strict on-device policy therefore continues to defer AI-generated pictures. Locally rendered charts and diagrams already work without a picture-generation model. [Image Playground](https://developer.apple.com/videos/play/wwdc2026/375/) · [ImageCreator discontinuation](https://developer.apple.com/news/?id=dz9wvq0r)
