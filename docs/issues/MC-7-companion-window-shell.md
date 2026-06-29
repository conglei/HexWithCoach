# [MC-7] macOS companion window shell

- **Phase:** 3 — Companion window
- **Depends on:** MC-3
- **Blocks:** MC-8, MC-9, MC-10, MC-11
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §3

## Goal
A real main window hosting the learning experience, native to the Mac, alongside the existing
menu bar.

## Tasks
- [ ] New main window (standalone SwiftUI + SwiftData `@Query` + `@Observable`, not TCA) with a
      `NavigationSplitView` sidebar: Review · Notebook · History · Progress · Settings.
- [ ] "Open Voco" menu-bar command + dock/Window-menu entry to surface it.
- [ ] Native Mac chrome: resizable, restores frame, toolbar; keep TCA pipeline untouched.
- [ ] Empty-state placeholders for each section (filled by MC-8..MC-11).

## Acceptance criteria
- [ ] Window opens from the menu bar, navigates between sections, restores size/position.
- [ ] `xcodebuild build -scheme VocoMac` succeeds; menu-bar dictation still works.

## Files
- `VocoMac/Views/` (new window), `VocoMac/App/HexAppDelegate.swift`
