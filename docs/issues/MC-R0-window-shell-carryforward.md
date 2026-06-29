# [MC-R0] Companion window shell (carried forward from MC-7)

- **Phase:** R — Reconcile with Phase-3
- **Carry-forward:** ✅ MC-7 carries forward almost verbatim
- **Depends on:** MC-R1
- **Blocks:** MC-R5, MC-R6, MC-R7, MC-R8
- **Size:** S (re-cut sections only)
- **Design:** [macos-companion-phase3-reconcile.md](../macos-companion-phase3-reconcile.md) §5–§6

## Goal
Keep MC-7's macOS main window (NSWindow + `NavigationSplitView`, "Open Voco" menu/status-item,
activation handling, shared `ModelContainer` in the SwiftUI environment). **Re-cut only the section
set** to the reconciled IA.

## Tasks
- [ ] Sidebar = **Coach · History · Settings** (+ a recents/quick-note pane per the capture decision).
- [ ] Rename/replace MC-7 placeholders: `MacReviewView`→`MacCoachView` (MC-R5), keep `MacHistoryView`
      (MC-R8), fold `MacProgressView` under Coach, drop standalone `MacNotebookView`.
- [ ] Keep the `ModelContainer` environment injection pointed at the re-founded shared store (MC-R2).

## Acceptance criteria
- [ ] Window opens, navigates Coach/History/Settings, restores frame; container reaches `@Query`.
- [ ] `xcodebuild build -scheme VocoMac` succeeds.
