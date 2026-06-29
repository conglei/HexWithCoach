---
"hex-app": patch
---

Add the macOS companion main window shell, re-cut to the reconciled Phase-3 IA (MC-R0). A native, resizable "Voco" window now opens alongside the menu bar — via left-clicking the status item, the new "Open Voco" status-menu item, app launch, and reopen. Its `NavigationSplitView` sidebar is Coach · History · Settings plus a recents / quick-note pane (capture stays the always-on menu-bar hotkey). Coach and History are named placeholder views (`MacCoachView`, `MacHistoryView`) wired for MC-R5 / MC-R8; Settings embeds the existing TCA settings UI. The shared SwiftData `ModelContainer` (MC-R3) is injected into the window's environment so the fan-out sections can `@Query`. Removes the now-orphaned `KeychainClient` (only used by the legacy coach removed in MC-R4).
