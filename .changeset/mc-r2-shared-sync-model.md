---
"hex-app": patch
---

Re-found the cross-platform shared SwiftData model (MC-R2): the Phase-3 `@Model` types (`TranscriptEntry`, `TranscriptAnalysis`, `CoachCardEntity`, `CoachObservation`, `PracticeItem`/`PracticeAttempt`) and the `TranscriptKind` enum now live in the shared `VocoEngine` layer alongside a centralized `SyncStore.makeContainer()` factory (CloudKit `iCloud.co.stonefrontier.voco` → local → in-memory) and `SyncPreferences`, so both the iOS (Voco) and macOS (VocoMac) apps compile one synced schema. iOS behavior is unchanged; the macOS app now carries the iCloud/CloudKit + App Group entitlements (MC-2).
