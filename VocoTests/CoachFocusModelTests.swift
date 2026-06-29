//
//  CoachFocusModelTests.swift
//  VocoTests
//
//  CF-1 — the app-side bridge from the persisted `CoachObservation` log to the
//  pure `ObservationFact`s the ranking consumes. The calibrated ranking itself is
//  unit-tested in VocoCore (`CoachFocusTests`); here we cover only the mapping the
//  app owns: the GOP → severity bucketing, which is what lets objective per-word
//  pronunciation rows participate in ranking at all.
//

import Foundation
import Testing
import VocoCore
@testable import Voco

struct CoachFocusModelTests {

    // MARK: - GOP → severity bucketing

    @Test
    func worseGOPMapsToHigherSeverity() {
        // GOP is ≤ 0; more negative = worse pronunciation = higher impact.
        #expect(CoachFocusModel.severity(forGOP: -6.0) == 5)
        #expect(CoachFocusModel.severity(forGOP: -4.5) == 4)
        #expect(CoachFocusModel.severity(forGOP: -3.2) == 3)
        #expect(CoachFocusModel.severity(forGOP: -2.1) == 2)
        #expect(CoachFocusModel.severity(forGOP: -1.0) == 1)
        #expect(CoachFocusModel.severity(forGOP: -0.2) == 1)
    }

    @Test
    func missingGOPIsLowestSeverity() {
        #expect(CoachFocusModel.severity(forGOP: nil) == 1)
    }

    @Test
    func severityIsMonotonicInGOP() {
        let gops = [-6.0, -5.0, -4.0, -3.0, -2.0, -1.0]
        let sevs = gops.map { CoachFocusModel.severity(forGOP: $0) }
        // As GOP improves (rises toward 0), severity must not increase.
        #expect(sevs == sevs.sorted(by: >))
    }
}
