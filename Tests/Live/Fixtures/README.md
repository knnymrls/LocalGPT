# Recorded speech fixture

`quiet-gardens.aiff` is synthetic speech generated locally with macOS `say -r 145` for the sentence “I prefer outdoor venues with quiet gardens.” It contains no microphone recording or personal audio. The opt-in live suite passes it through the production audio converter and local Whisper runtime. This checks recognition independently of Simulator microphone routing.

# Image-input test fixture

`photo.jpg` is **Cat03.jpg**, by **Fir0002/Flagstaffotos**.

Source: https://commons.wikimedia.org/wiki/File:Cat03.jpg
Original: https://upload.wikimedia.org/wikipedia/commons/3/3a/Cat03.jpg

Used unmodified under the **GNU Free Documentation License, version 1.2 only**, with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts:
https://www.gnu.org/licenses/old-licenses/fdl-1.2.html

This image retains that license independently of the application source. It is bundled only in the opt-in test target. The neutral filename and OCR-only extraction ensure the visual test cannot infer the animal from the attachment name or a hand-authored description.
