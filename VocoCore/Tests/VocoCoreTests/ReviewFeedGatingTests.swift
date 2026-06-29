import XCTest
@testable import VocoCore

/// CI-5: keyless-first Review gating. The crux is that the feed never gates on
/// key presence — objective cards show with no key — and the upsell is purely a
/// function of key absence, never a content blocker.
final class ReviewFeedGatingTests: XCTestCase {

    // MARK: - Feed state

    func testCardsAlwaysShowFeed_evenWithoutKey() {
        // The regression this whole task exists to prevent: keyless cards present
        // → feed, no key wall.
        let inputs = ReviewFeedGating.Inputs(hasCards: true, hasKey: false, hasNotes: true)
        XCTAssertEqual(ReviewFeedGating.feedState(inputs), .feed)
    }

    func testCardsShowFeedWithKey() {
        let inputs = ReviewFeedGating.Inputs(hasCards: true, hasKey: true, hasNotes: true)
        XCTAssertEqual(ReviewFeedGating.feedState(inputs), .feed)
    }

    func testNoCardsButNotes_isCaughtUp_notKeyWall() {
        let keyless = ReviewFeedGating.Inputs(hasCards: false, hasKey: false, hasNotes: true)
        let keyed = ReviewFeedGating.Inputs(hasCards: false, hasKey: true, hasNotes: true)
        XCTAssertEqual(ReviewFeedGating.feedState(keyless), .caughtUp)
        XCTAssertEqual(ReviewFeedGating.feedState(keyed), .caughtUp)
    }

    func testNoCardsNoNotes_isOnboarding_regardlessOfKey() {
        let keyless = ReviewFeedGating.Inputs(hasCards: false, hasKey: false, hasNotes: false)
        let keyed = ReviewFeedGating.Inputs(hasCards: false, hasKey: true, hasNotes: false)
        XCTAssertEqual(ReviewFeedGating.feedState(keyless), .onboarding)
        XCTAssertEqual(ReviewFeedGating.feedState(keyed), .onboarding)
    }

    // MARK: - Upsell

    func testUpsellShownExactlyWhenNoKey() {
        for hasCards in [true, false] {
            for hasNotes in [true, false] {
                let noKey = ReviewFeedGating.Inputs(hasCards: hasCards, hasKey: false, hasNotes: hasNotes)
                let withKey = ReviewFeedGating.Inputs(hasCards: hasCards, hasKey: true, hasNotes: hasNotes)
                XCTAssertTrue(ReviewFeedGating.showsKeyUpsell(noKey),
                              "Upsell should show without a key (cards=\(hasCards), notes=\(hasNotes))")
                XCTAssertFalse(ReviewFeedGating.showsKeyUpsell(withKey),
                               "Upsell should be hidden with a key (cards=\(hasCards), notes=\(hasNotes))")
            }
        }
    }

    /// The upsell must never suppress content: it can co-exist with the live feed.
    func testUpsellNeverBlocksKeylessFeed() {
        let inputs = ReviewFeedGating.Inputs(hasCards: true, hasKey: false, hasNotes: true)
        XCTAssertEqual(ReviewFeedGating.feedState(inputs), .feed)
        XCTAssertTrue(ReviewFeedGating.showsKeyUpsell(inputs))
    }
}
