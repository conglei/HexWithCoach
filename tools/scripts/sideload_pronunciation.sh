#!/usr/bin/env bash
# Copy the pronunciation assets into the HexIOS app container (simulator or a
# physical device) so the app loads them at runtime from
# Application Support/Pronunciation/.
#
# Why sideload instead of bundling: this Xcode's build-time Core ML compiler can't
# process the coremltools-9 model (plist error), but the OS *runtime* Core ML can —
# so we load it at runtime from Application Support instead of the app bundle.
#
# Prereqs: run HexIOS once (from Xcode) on the target so the app container exists.
#
# Usage:
#   ./tools/scripts/sideload_pronunciation.sh                 # booted simulator
#   ./tools/scripts/sideload_pronunciation.sh device          # first connected device
#   ./tools/scripts/sideload_pronunciation.sh device <UDID>   # specific device
#   ./tools/scripts/sideload_pronunciation.sh mac             # macOS app (Debug build)
#   ./tools/scripts/sideload_pronunciation.sh mac <bundle-id> # macOS app (other build)
set -euo pipefail

BUNDLE_ID="co.stonefrontier.voco"
ASSETS="$(cd "$(dirname "$0")/../pronunciation-assets" && pwd)"
TARGET="${1:-sim}"

if [[ "$TARGET" == "parakeet" ]]; then
  # Sideload the Parakeet ASR model from the Mac's cache, bypassing FluidAudio's
  # in-memory download (which OOM-kills the app on the big weight file).
  DEVICE="${2:-$(xcrun devicectl list devices 2>/dev/null | grep -i connected | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)}"
  SRC="$HOME/Library/Containers/co.stonefrontier.voco/Data/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml"
  # Fall back to the pre-rename macOS Hex container if the model was cached there.
  [[ -d "$SRC" ]] || SRC="$HOME/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml"
  [[ -d "$SRC" ]] || { echo "No cached Parakeet model at: $SRC"; exit 1; }
  [[ -z "$DEVICE" ]] && { echo "No connected device found. Pass a UDID."; exit 1; }
  echo "Pushing Parakeet (~461MB) to device $DEVICE … (USB; takes a minute)"
  xcrun devicectl device copy to \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "$SRC" \
    --destination "Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml"
  echo "✓ Parakeet sideloaded. Force-quit and relaunch the app — no download needed."
  exit 0
fi

if [[ "$TARGET" == "mac" ]]; then
  # macOS app (sandboxed): copy the phoneme assets into the app's *container*
  # Application Support, where MacPronunciationAssets loads them at runtime
  # (same Pronunciation/ convention as iOS). Bundle id defaults to the Debug
  # build; pass one to target another build, e.g. `mac co.stonefrontier.voco`.
  # Prereq: launch VocoMac once so its container exists.
  MAC_BUNDLE="${2:-co.stonefrontier.voco.debug}"
  CONTAINER="$HOME/Library/Containers/$MAC_BUNDLE/Data"
  [[ -d "$CONTAINER" ]] || { echo "No container for $MAC_BUNDLE — launch VocoMac once first, then re-run."; exit 1; }
  DEST="$CONTAINER/Library/Application Support/Pronunciation"
  rm -rf "$DEST"        # clear any previous (e.g. old model) so nothing stale remains
  mkdir -p "$DEST"
  cp -R "$ASSETS/PhonemeCTC.mlpackage" "$DEST/"
  cp "$ASSETS/cmudict.dict" "$ASSETS/phoneme_vocab.json" "$DEST/"
  echo "✓ Sideloaded to macOS app ($MAC_BUNDLE): $DEST"
  echo "Force-quit and relaunch VocoMac — word-level pronunciation now runs."
  exit 0
fi

if [[ "$TARGET" == "sim" ]]; then
  CONTAINER="$(xcrun simctl get_app_container booted "$BUNDLE_ID" data)"
  DEST="$CONTAINER/Library/Application Support/Pronunciation"
  rm -rf "$DEST"        # clear any previous (e.g. old model) so nothing stale remains
  mkdir -p "$DEST"
  cp -R "$ASSETS/PhonemeCTC.mlpackage" "$DEST/"
  cp "$ASSETS/cmudict.dict" "$ASSETS/phoneme_vocab.json" "$DEST/"
  echo "✓ Sideloaded to simulator: $DEST"
else
  # Physical device via devicectl. Stage a folder literally named "Pronunciation"
  # and push it into the app's data container.
  DEVICE="${2:-$(xcrun devicectl list devices 2>/dev/null | grep -i connected | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)}"
  if [[ -z "$DEVICE" ]]; then echo "No connected device found. Pass a UDID."; exit 1; fi
  STAGE="$(mktemp -d)/Pronunciation"
  mkdir -p "$STAGE"
  cp -R "$ASSETS/PhonemeCTC.mlpackage" "$ASSETS/cmudict.dict" "$ASSETS/phoneme_vocab.json" "$STAGE/"
  echo "Pushing ~300MB to device $DEVICE …"
  xcrun devicectl device copy to \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "$STAGE" \
    --destination "Library/Application Support/Pronunciation"
  echo "✓ Sideloaded to device $DEVICE"
fi

echo "Force-quit and relaunch the app, then record/open a note — pronunciation now runs automatically and shows inline."
