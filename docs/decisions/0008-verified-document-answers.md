# 0008 Verifiable document answers

Date: 2026-10-03. Status: implemented; live evaluation continues.

The real Files-picker demonstration exposed two failures missed by the original shallow checks: the local model reused an old seating value after a requirement changed, and free-form table generation sometimes padded a cell with thousands of spaces. Inspection also found an extracted question incorrectly saved as user context.

## Decisions

- Final source writing uses retrieved passages and prior user turns, excluding earlier generated answers as evidence.
- General source answers use guided paragraphs and bounded table cells. Swift renders Markdown; generation schemas are included in the context budget.
- A single explicit number-and-unit requirement is parsed directly when every selected source has one unambiguous matching value. Other numeric questions get a separate extraction pass for requirements. The extractor sees only the latest question and source passages. Swift computes at-least, at-most, or exact qualification after validating the requirement quote, source quotes, numeric values, adjacent units, names, and source coverage.
- Invalid or duplicate extraction candidates are discarded. A claimed numeric comparison with no verified candidate fails visibly. Numeric results include the underlying source details and citations instead of asking the model to rewrite the computed verdict.
- PDF/text/Markdown reports containing a numeric source requirement reuse the verified comparison. Successful file receipts come from committed outputs rather than a generated postamble. A failure after a file write keeps that file inspectable and labels any remaining response as unfinished.
- Memory validation rejects imperative requests as well as common interrogative forms and question punctuation independently of the model. Receipt semantics remain commit-before-display.
- Files persist by attachment identity and filename, resolved against the current sandbox; legacy absolute URLs are rebased when loaded.

## Tradeoffs

Extraction and semantic interpretation remain probabilistic. These checks prove quoted values and arithmetic, not that every possible question is understood. The numeric path requires shared explicit units and coverage of selected sources; broader unit conversion, dates, and complex constraints remain unsupported. It may ask the user to clarify rather than guess. Structured source answers add some latency, measured separately from ordinary chat.

The evaluation now checks actual qualification and usable response shape, not just whether an answer mentions the venue names. See [verification](../verification.md) for current observed results and remaining microphone/offline/device gates.
