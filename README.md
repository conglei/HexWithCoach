# Voco

**Voco** is an on-device dictation and English-coaching app by **StoneFrontier**.
Speak naturally and Voco transcribes locally, then helps you sound more fluent —
pronunciation and fluency are analyzed on-device, with an optional bring-your-own-key
AI lane for deeper review.

> Voco is a closed-source, proprietary application. It is **not** open source.

## What's in this repo

This repository contains the Voco app and its components:

- **macOS app** (`Hex/`) — the menu-bar voice-to-text app, derived from Hex.
- **iOS app** (`HexIOS/`) — the on-device dictation app with the English Coach
  (Review, Shadowing, Phrasebook, Progress).
- **Custom keyboard extension** (`HexIOSKeyboard/`) — a Wispr-style on-device
  dictation keyboard.
- **Shared core** (`HexCore/`, `HexEngine/`) — cross-platform transcription and
  Coach engine logic (LearnerProfile, FluencySignals, CoachPipeline, etc.).

Transcription runs fully on-device via [Parakeet TDT v3](https://github.com/FluidInference/FluidAudio)
(through [FluidAudio](https://github.com/FluidInference/FluidAudio), the default)
and [WhisperKit](https://github.com/argmaxinc/WhisperKit). The app is structured
with the [Swift Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture).

## Built on Hex

Voco is built on **[Hex](https://github.com/kitlangton/Hex)** by Kit Langton,
used under the **MIT License**. Hex is a wonderful on-device voice-to-text app
for macOS, and Voco extends it into a cross-platform dictation + coaching
product.

See [`LICENSE`](LICENSE) for the Hex MIT license and
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) for the full attribution of
all third-party components. The same attributions are reproduced in-app under
**Settings ▸ About ▸ Acknowledgements**.

## Credits

- **Hex** by Kit Langton — MIT (<https://github.com/kitlangton/Hex>)
- **FluidAudio / Parakeet TDT v3** — on-device ASR
- **WhisperKit** — on-device ASR
- **Swift Composable Architecture** — app architecture
- and the many other open-source and licensed components listed in
  [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

## License

Voco is proprietary software © StoneFrontier. All rights reserved. The bundled
upstream Hex code is licensed under the MIT License (see [`LICENSE`](LICENSE));
third-party components retain their own licenses (see
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md)).
