//
//  PracticeStore.swift
//  Voco
//
//  Practice items (PR-1) — target text the learner practices via the shadowing
//  loop (TTS → speak → ASR/GOP score). Coach-card, phrasebook, and pasted/typed
//  targets are NOT captures: they're modeled as their *own* type, deliberately
//  separate from `TranscriptEntry`, so they can never surface in History queries.
//
//  The `@Model` types (`PracticeItem` + `PracticeAttempt`) now live in the shared
//  VocoEngine layer (`VocoEngine/SyncModels.swift`) so both the iOS and macOS
//  targets compile them into one synced schema (MC-R2). This file keeps the
//  iOS-facing creation helpers that consume them.
//

import Foundation
import SwiftData
import VocoCore

/// Minimal creation helpers for `PracticeItem`. Kept intentionally small — the
/// model + container registration is the PR-1 deliverable; the UI (PR-2) and the
/// paste flow (PR-3) build on top of this.
enum PracticeStore {
    /// Build a practice item from raw pasted/typed text. Pasted text is always a
    /// shadowing target (no source insight to drive another drill kind).
    static func pasted(_ text: String, segments: [String], title: String? = nil) -> PracticeItem {
        PracticeItem(title: title, sourceText: text, segments: segments, origin: .pasted, kind: .shadow)
    }

    /// Build a practice item sourced from a coach card / insight. `kind` defaults to
    /// `.shadow` to preserve every existing caller; CF-2's lens→drill wiring passes
    /// `.wordSwap` for lexis cards so the attempt persists tagged with its drill.
    ///
    /// CF-3: `patternKey` + `lens` tag the item with the focus area it was launched to
    /// address, so the recorded attempt is attributable to a `(lens, patternKey)` and
    /// can close the loop with that pattern's frequency trend. Both default to nil so
    /// every existing caller is unchanged.
    static func coachInsight(
        _ text: String, segments: [String], sourceID: UUID,
        kind: PracticeKind = .shadow, patternKey: String? = nil, lens: Lens? = nil,
        title: String? = nil
    ) -> PracticeItem {
        PracticeItem(
            title: title, sourceText: text, segments: segments, origin: .coachInsight,
            kind: kind, sourceID: sourceID, patternKey: patternKey, lens: lens
        )
    }

    /// Build a practice item sourced from a phrasebook entry.
    static func phrasebook(_ text: String, segments: [String], sourceID: UUID, title: String? = nil) -> PracticeItem {
        PracticeItem(title: title, sourceText: text, segments: segments, origin: .phrasebook, sourceID: sourceID)
    }
}
