---
"hex-app": patch
---

Testing: stand up the `HexIOSTests` unit-test target so iOS app code (and HexEngine as compiled into the iOS module) is finally testable via `xcodebuild test -scheme HexIOS`. Hosted by the HexIOS app, wired into the HexIOS scheme, with initial coverage for `SessionLength` and `TranscriptKind`. The target was added with the `xcodeproj` gem (script kept under `scripts/` for reproducibility) so the project file stayed consistent (clean +130-line addition, no reformat). Completes the three-runner test setup documented in CLAUDE.md: HexCore `swift test`, the `HexTests` macOS bundle, and now `HexIOSTests`.
