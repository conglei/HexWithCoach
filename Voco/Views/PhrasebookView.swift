//
//  PhrasebookView.swift
//  HexIOS
//
//  The phrasebook (RC-5): a lightweight retention layer. Tapping "Save" on a
//  Review card files its natural phrasing here for later flick-through review.
//  Deliberately flat — no folders, no tags (spaced repetition is deferred to
//  v2.1). Reached from the Review tab.
//

import VocoCore
import SwiftData
import SwiftUI

struct PhrasebookView: View {
    @Query(
        filter: #Predicate<CoachCardEntity> { $0.statusRaw == "saved" },
        sort: \CoachCardEntity.createdAt, order: .reverse
    )
    private var saved: [CoachCardEntity]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if saved.isEmpty {
                ContentUnavailableView(
                    "No saved phrasings yet",
                    systemImage: "bookmark",
                    description: Text("Tap Save on a Review card to keep its natural phrasing here.")
                )
            } else {
                List {
                    ForEach(saved) { card in
                        row(card)
                    }
                    .onDelete(perform: remove)
                }
            }
        }
        .navigationTitle("Phrasebook")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ card: CoachCardEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.nativeRewrite ?? card.title)
                .font(.body)
                .foregroundStyle(Color.accentColor)
            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { unsave(card) } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets { unsave(saved[index]) }
    }

    /// "Removing" from the phrasebook just clears the saved status (the card is
    /// already out of the feed), so nothing is destroyed.
    private func unsave(_ card: CoachCardEntity) {
        card.status = .done
        try? modelContext.save()
    }
}
