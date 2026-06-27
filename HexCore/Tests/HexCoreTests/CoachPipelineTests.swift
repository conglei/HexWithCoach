import Foundation
import Testing
@testable import HexCore

/// A scripted CoachLLM: returns canned extract/critic JSON by tier, and records
/// the prompts it was given so we can assert on personalization.
private final class MockCoachLLM: CoachLLM, @unchecked Sendable {
    let extractJSON: String
    let criticJSON: String
    var lastExtractUserPrompt: String?
    var lastCriticUserPrompt: String?
    var sawAudioOnExtract = false
    var sawAudioOnCritic = false

    init(extractJSON: String, criticJSON: String) {
        self.extractJSON = extractJSON
        self.criticJSON = criticJSON
    }

    func generateJSON(systemPrompt: String, userPrompt: String, audio: CoachAudio?, tier: CoachModelTier) async throws -> String {
        switch tier {
        case .extract:
            lastExtractUserPrompt = userPrompt
            sawAudioOnExtract = (audio != nil)
            return extractJSON
        case .critic:
            lastCriticUserPrompt = userPrompt
            sawAudioOnCritic = (audio != nil)
            return criticJSON
        }
    }
}

struct CoachPipelineTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let transcriptID = UUID()

    private func input(_ text: String = "Me and him went to store yesterday, um, like, it was good.") -> CoachTranscriptInput {
        CoachTranscriptInput(id: transcriptID, text: text, durationSec: 12)
    }

    private let twoCandidates = """
    {"candidates":[
      {"lens":"grammar","key":"missing-article","summary":"drops articles","span":"went to store","rule":"Use 'the' before singular count nouns.","nativeRewrite":"went to the store","severity":3,"needsAudio":false},
      {"lens":"lexis","key":"filler-like","summary":"discourse filler","span":"like, it was good","rule":"Drop 'like' as filler.","nativeRewrite":"it was good","severity":2,"needsAudio":false}
    ]}
    """

    @Test
    func verifiedCandidatesBecomeInsightsAndUpdateProfile() async throws {
        // Critic accepts candidate 0, rejects 1 (not a real error).
        let critic = """
        {"verdicts":[
          {"index":0,"isRealError":true,"rewriteIsBetter":true,"confidence":0.92},
          {"index":1,"isRealError":false,"rewriteIsBetter":false,"confidence":0.3}
        ]}
        """
        let pipeline = CoachPipeline(llm: MockCoachLLM(extractJSON: twoCandidates, criticJSON: critic))
        var profile = LearnerProfile()

        let analysis = try await pipeline.analyze(input(), profile: &profile, at: t0)

        #expect(analysis.insights.count == 1)
        #expect(analysis.insights.first?.key == "missing-article")
        #expect(analysis.insights.first?.nativeRewrite == "went to the store")
        // Only the surviving observation is merged into the profile.
        #expect(profile.patterns.count == 1)
        #expect(profile.patterns.first?.key == "missing-article")
        #expect(profile.patterns.first?.frequency == 1)
        // A focus is named.
        #expect(analysis.focuses.count == 1)
        #expect(analysis.focuses.first?.patternKey == "missing-article")
    }

    @Test
    func criticRejectsAllLeavesProfileUntouched() async throws {
        let critic = """
        {"verdicts":[
          {"index":0,"isRealError":false,"rewriteIsBetter":false,"confidence":0.1},
          {"index":1,"isRealError":true,"rewriteIsBetter":true,"confidence":0.4}
        ]}
        """ // index 1 is "real" but below the 0.6 confidence threshold → dropped
        let pipeline = CoachPipeline(llm: MockCoachLLM(extractJSON: twoCandidates, criticJSON: critic))
        var profile = LearnerProfile()

        let analysis = try await pipeline.analyze(input(), profile: &profile, at: t0)
        #expect(analysis.insights.isEmpty)
        #expect(profile.patterns.isEmpty)
        #expect(analysis.focuses.isEmpty)
    }

    @Test
    func recurringIssueAcrossRunsRaisesFrequency() async throws {
        let critic = """
        {"verdicts":[{"index":0,"isRealError":true,"rewriteIsBetter":true,"confidence":0.9}]}
        """
        let oneCandidate = """
        {"candidates":[{"lens":"grammar","key":"missing-article","summary":"drops articles","span":"went to store","rule":"r","nativeRewrite":"went to the store","severity":3,"needsAudio":false}]}
        """
        let pipeline = CoachPipeline(llm: MockCoachLLM(extractJSON: oneCandidate, criticJSON: critic))
        var profile = LearnerProfile()

        _ = try await pipeline.analyze(input(), profile: &profile, at: t0)
        _ = try await pipeline.analyze(input(), profile: &profile, at: t0.addingTimeInterval(3600))

        #expect(profile.patterns.count == 1)
        #expect(profile.patterns.first?.frequency == 2)
    }

    @Test
    func emptyExtractionShortCircuits() async throws {
        let pipeline = CoachPipeline(llm: MockCoachLLM(extractJSON: #"{"candidates":[]}"#, criticJSON: "{}"))
        var profile = LearnerProfile()
        let analysis = try await pipeline.analyze(input(), profile: &profile, at: t0)
        #expect(analysis.insights.isEmpty)
        #expect(profile.patterns.isEmpty)
        // Local signals are still computed even with nothing to flag.
        #expect(analysis.signals.fillerCount >= 1)
    }

    @Test
    func extractPromptCarriesProfileAndSignals() async throws {
        let mock = MockCoachLLM(extractJSON: #"{"candidates":[]}"#, criticJSON: "{}")
        let pipeline = CoachPipeline(llm: mock)
        var profile = LearnerProfile(inferredL1: "Mandarin")
        profile.integrate([VerifiedObservation(
            lens: .grammar, key: "missing-article", summary: "drops articles",
            rule: "r", example: ExampleRef(transcriptID: UUID(), span: "to store")
        )], at: t0)

        _ = try await pipeline.analyze(input(), profile: &profile, at: t0)
        let prompt = try #require(mock.lastExtractUserPrompt)
        #expect(prompt.contains("Mandarin"))
        #expect(prompt.contains("missing-article"))   // existing pattern key offered for reuse
        #expect(prompt.contains("fillers/min"))        // objective signals included
    }

    @Test
    func toleratesMarkdownFencedJSON() throws {
        let fenced = """
        Here is the result:
        ```json
        {"candidates":[{"lens":"prosody","key":"x","summary":"s","span":"sp","rule":"r","nativeRewrite":"nr","severity":1,"needsAudio":true}]}
        ```
        """
        let decoded = try CoachPipeline.decodeJSON(ExtractionResponse.self, from: fenced)
        #expect(decoded.candidates.count == 1)
        #expect(decoded.candidates.first?.lens == .prosody)
    }

    @Test
    func audioIsForwardedToExtraction() async throws {
        let critic = #"{"verdicts":[]}"#
        let mock = MockCoachLLM(extractJSON: #"{"candidates":[]}"#, criticJSON: critic)
        let pipeline = CoachPipeline(llm: mock)
        var profile = LearnerProfile()
        var inp = input()
        inp.audio = CoachAudio(data: Data([0x01, 0x02]), mimeType: "audio/wav")
        _ = try await pipeline.analyze(inp, profile: &profile, at: t0)
        #expect(mock.sawAudioOnExtract)
    }

    @Test
    func criticHearsAudioOnlyWhenACandidateNeedsIt() async throws {
        let critic = """
        {"verdicts":[{"index":0,"isRealError":false,"rewriteIsBetter":false,"confidence":0.1}]}
        """
        // Text-only candidate: the critic should be called without audio.
        let textOnly = """
        {"candidates":[{"lens":"grammar","key":"missing-article","summary":"s","span":"went to store","rule":"r","nativeRewrite":"went to the store","severity":3,"needsAudio":false}]}
        """
        let mockText = MockCoachLLM(extractJSON: textOnly, criticJSON: critic)
        var profileText = LearnerProfile()
        var inpText = input()
        inpText.audio = CoachAudio(data: Data([0x01]), mimeType: "audio/wav")
        _ = try await CoachPipeline(llm: mockText).analyze(inpText, profile: &profileText, at: t0)
        #expect(mockText.sawAudioOnCritic == false)

        // Audio-dependent candidate (pronunciation): the critic should hear it.
        let needsAudio = """
        {"candidates":[{"lens":"pronunciation","key":"th-stopping","summary":"s","span":"think","rule":"r","nativeRewrite":"think","severity":3,"needsAudio":true}]}
        """
        let mockAudio = MockCoachLLM(extractJSON: needsAudio, criticJSON: critic)
        var profileAudio = LearnerProfile()
        var inpAudio = input()
        inpAudio.audio = CoachAudio(data: Data([0x01]), mimeType: "audio/wav")
        _ = try await CoachPipeline(llm: mockAudio).analyze(inpAudio, profile: &profileAudio, at: t0)
        #expect(mockAudio.sawAudioOnCritic)
    }
}
