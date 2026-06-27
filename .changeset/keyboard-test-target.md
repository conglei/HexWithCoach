---
"hex-app": patch
---

Testing: add a `HexIOSKeyboardTests` target so the keyboard extension finally has unit coverage. App-extension modules can't be linked from a test bundle, so the keyboard's state machine (`KeyboardPhase` / `KeyboardState` / `KeyboardActions`) is extracted from `KeyboardView.swift` into its own UIKit-free `KeyboardState.swift`, which the test target compiles directly. Initial tests cover the six-state `phase` derivation (no-Full-Access precedence, capturing → recording, expired session → needs-bounce) and the "MM:SS" countdown formatting. Runs via `xcodebuild test -scheme HexIOS`.
