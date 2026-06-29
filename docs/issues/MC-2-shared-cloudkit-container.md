# [MC-2] Shared CloudKit container + cross-device merge spike

- **Phase:** 1 — Unify model + sync
- **Depends on:** MC-1
- **Blocks:** MC-3, MC-4
- **Size:** M
- **Design:** [macos-companion-v1-design.md](../macos-companion-v1-design.md) §2, §5
- **Risk:** High — must be verified on real devices/iCloud before building on it.

## Goal
Both apps point at the **same** CloudKit container so records merge Mac↔iOS. De-risk the whole
plan with an early round-trip test.

## Tasks
- [ ] Choose one explicit CloudKit container ID (e.g. `iCloud.<shared-id>`); add to **both**
      `Voco/Voco.entitlements` and `VocoMac/VocoMac.entitlements`
      (`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services = CloudKit`).
- [ ] Pass the explicit container to the shared `ModelConfiguration(cloudKitDatabase:)` factory
      (not `.automatic`-derived) so both bundle IDs target the same container.
- [ ] Conflict policy: last-writer-wins keyed by record `id`; dedupe on `id`.
- [ ] **Spike:** create a note on one platform, confirm it appears on the other.

## Acceptance criteria
- [ ] A dictation created on iOS appears in macOS history and vice versa (device/iCloud verified).
- [ ] No duplicate records after repeated sync cycles.

## Notes
- App Group ≠ CloudKit container. Requires Apple Developer account config + signed builds with an
  iCloud account; **flag for owner device test** — an agent can land the code/entitlements but
  cannot verify the live merge in a sandbox.

## Files
- `Voco/Voco.entitlements`, `VocoMac/VocoMac.entitlements`, `VocoEngine/SyncStore.swift`
