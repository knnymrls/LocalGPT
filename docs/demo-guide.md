# LocalGPT conversation starters

The empty chat offers four editable examples. Each includes fictional sample input, needs no upload, and starts a real model request only when the person presses Send. No assistant replies or output files are preloaded. Every example opts out of memory.

| Starter | What to highlight | Follow-up to try |
| --- | --- | --- |
| Turn notes into a plan | Extract three owners, tasks, and deadlines into a concise checklist. | “Move Lee's deadline to Friday and show only the updated checklist.” |
| Build a CSV tracker | Create a spreadsheet from three fictional expenses, with numeric amounts. | “Create a new CSV version with a Coffee row for 5 dollars.” |
| Create a PDF checklist | Open and share an actual generated file from Outputs. | “Create a new PDF version with a reminder to test the microphone.” |
| Make a budget chart | Produce a locally rendered PNG from supplied numbers. | “Create a new chart with Food increased to 300 dollars.” |

These follow-ups are demonstration ideas, not assertions that every response has been verified. Current observed checks are in verification.md. People can replace the sample input with their own details before sending.

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
