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
//  IA-2 — capture-first activation. With the front door now Home (not Coach),
//  this banner doubles as the *baited* pre-activation hero: when a real capture
//  count is available it leads with "You've captured N things this week — see
//  how to say them better," selling the payoff using the user's own corpus
//  rather than opening with BYOK mechanics.
//

import SwiftUI

struct KeyUpsellBanner: View {
    /// Tapping the banner takes the user to Settings to connect a key.
    let onConnect: () -> Void
    /// Number of notes captured this week, used to bait the pre-activation
    /// pitch with the user's real corpus (IA-2). `nil` (or 0) falls back to the
    /// generic upsell copy.
    var capturedThisWeek: Int = 0

    private var headline: String {
        capturedThisWeek > 0
            ? "See how to say them better"
            : "Unlock more coaching"
    }

    private var pitch: String {
        capturedThisWeek > 0
            ? "You've captured \(capturedThisWeek) thing\(capturedThisWeek == 1 ? "" : "s") this week. Turn on coaching to get grammar, word choice, clarity, and intonation feedback on your own speech — pronunciation & fluency are already free and on-device."
            : "Pronunciation & fluency are free and on-device. Add an AI key to also get grammar, word choice, clarity, and intonation feedback."
    }

    var body: some View {
        Button(action: onConnect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HexTheme.gradient)
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(pitch)
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
