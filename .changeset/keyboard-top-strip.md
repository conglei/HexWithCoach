---
"hex-app": minor
---

Redesign the iOS dictation keyboard around a top toolbar strip. Above a standard QWERTY layout, an idle strip shows the next-keyboard globe, a prominent blue "Tap to dictate" pill, and a settings button (opens the Hex app's Settings); while recording the strip becomes "Cancel" + a red "Tap to stop" pill with a listening waveform, and the keys dim underneath. Removes the bottom-right corner mic in favor of the always-visible top pill. Also fixes a layout bug where the bottom letter rows collapsed (key widths are now distributed proportionally instead of via layoutPriority). Adds a `hexkb://settings` deep link so the keyboard's settings button lands on the Settings tab.
