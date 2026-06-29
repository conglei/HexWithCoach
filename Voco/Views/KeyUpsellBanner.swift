//
//  KeyUpsellBanner.swift
//  HexIOS
//
//  CI-5 — the non-blocking key upsell. The objective lane already coaches
//  pronunciation + fluency for free (ADR-0002), so a BYOK key is no longer a
//  gate; it's an enhancement that unlocks the meaning lenses (grammar / word
//  choice / clarity), the intonation lens, and richer LLM-authored teaching.
//  This banner advertises that without ever blocking the keyless feed.
//

import SwiftUI

struct KeyUpsellBanner: View {
    /// Tapping the banner takes the user to Settings to connect a key.
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HexTheme.gradient)
                    Text("Unlock more coaching")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text("Pronunciation & fluency are free and on-device. Add an AI key to also get grammar, word choice, clarity, and intonation feedback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
