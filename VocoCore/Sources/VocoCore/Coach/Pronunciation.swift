import Foundation
import os
#if canImport(CoreML)
import CoreML
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Results (pure)

/// One aligned phoneme with its time interval and a Goodness-of-Pronunciation
/// score: `gop ≤ 0`, closer to 0 = the audio confidently matched the expected
/// phoneme; very negative = likely mispronounced.
public struct PhonemeScore: Sendable, Equatable, Codable {
    public let symbol: String       // expected IPA (what the word calls for)
    public let start: Double        // seconds
    public let end: Double
    public let gop: Double
    /// The most-likely *actually-pronounced* IPA over this phoneme's span (the mode
    /// of the model's per-frame argmax, excluding blank). `nil` when undetermined.
    /// Equal to `symbol` when the learner produced the expected sound; differs when
    /// they substituted another sound — which is what makes "expected → you said"
    /// feedback possible. Optional + `decodeIfPresent` keeps old persisted data valid.
    public let actualSymbol: String?
    public init(symbol: String, start: Double, end: Double, gop: Double, actualSymbol: String? = nil) {
        self.symbol = symbol; self.start = start; self.end = end; self.gop = gop
        self.actualSymbol = actualSymbol
    }
}

/// A word with its constituent phoneme scores.
public struct WordScore: Sendable, Equatable, Codable {
    public let word: String
    public let phonemes: [PhonemeScore]
    public init(word: String, phonemes: [PhonemeScore]) { self.word = word; self.phonemes = phonemes }
    /// Mean GOP across the word's phonemes.
    public var gop: Double { phonemes.isEmpty ? 0 : phonemes.map(\.gop).reduce(0, +) / Double(phonemes.count) }
}

public struct PronunciationResult: Sendable, Equatable, Codable {
    public let words: [WordScore]
    public init(words: [WordScore]) { self.words = words }
    public var overall: Double {
        let all = words.flatMap(\.phonemes)
        return all.isEmpty ? 0 : all.map(\.gop).reduce(0, +) / Double(all.count)
    }
}

// MARK: - On-device model location (sideload / download target)

/// The on-disk layout of the on-device pronunciation assets.
///
/// The phoneme CTC model is loaded from `<Application Support>/Pronunciation/`
/// (the historical dev "sideload" directory). The download-on-demand delivery
/// (CI-8) targets this same directory so runtime loading via `PronunciationAnalyzer`
/// is unchanged whether the model was sideloaded or downloaded.
public enum PronunciationModelLocation {
    /// The model bundle name the runtime loads (an unpacked `.mlpackage`).
    public static let modelFileName = "PhonemeCTC.mlpackage"

    /// `<Application Support>/Pronunciation/`, created if needed.
    public static func directory(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent("Pronunciation", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The destination URL for the model inside the sideload directory.
    public static func modelURL(fileManager: FileManager = .default) throws -> URL {
        try directory(fileManager: fileManager).appendingPathComponent(modelFileName)
    }

    /// Whether the model is present on disk (downloaded or sideloaded). Does not
    /// check the app bundle — a bundled model never needs a download.
    public static func isInstalled(fileManager: FileManager = .default) -> Bool {
        guard let url = try? modelURL(fileManager: fileManager) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
}

public enum PronunciationError: Error, LocalizedError {
    case noAudioFrames
    case noRecognizableWords
    case clipTooShort
    case alignmentFailed
    case modelOutputMissing
    case unsupportedAudioFormat

    public var errorDescription: String? {
        switch self {
        case .noAudioFrames: return "Couldn't read any audio."
        case .noRecognizableWords: return "No words found in the pronunciation dictionary."
        case .clipTooShort: return "The clip is too short for its words."
        case .alignmentFailed: return "Couldn't align the audio to the words."
        case .modelOutputMissing: return "The phoneme model produced no output."
        case .unsupportedAudioFormat: return "Audio must be 16 kHz mono."
        }
    }
}

// MARK: - G2P (pure)

/// Grapheme-to-phoneme via CMUdict, mapped from ARPAbet to the eSpeak-IPA symbols
/// the phoneme model emits. Pure Foundation — load a CMUdict `.dict` file and look
/// up words; out-of-dictionary words return nil (the caller skips them).
public final class PhonemeG2P {
    private let dict: [String: [String]]   // word -> IPA symbols

    public init?(cmudictURL: URL) {
        guard let text = try? String(contentsOf: cmudictURL, encoding: .utf8) else { return nil }
        var d: [String: [String]] = [:]
        for rawLine in text.split(separator: "\n") {
            if rawLine.hasPrefix(";;;") { continue }
            let parts = rawLine.split(separator: " ")
            guard parts.count >= 2 else { continue }
            let word = String(parts[0])
            if word.contains("(") { continue }        // skip "word(2)" alternates
            let key = word.lowercased()
            if d[key] != nil { continue }              // keep first pronunciation
            let ipa = parts[1...].compactMap { Self.mapPhone(String($0)) }
            if ipa.count == parts.count - 1 { d[key] = ipa }
        }
        guard !d.isEmpty else { return nil }
        self.dict = d
    }

    /// IPA phonemes for a word, or nil if out-of-dictionary.
    public func phonemes(for word: String) -> [String]? {
        let key = word.lowercased().filter { $0.isLetter || $0 == "'" }
        guard !key.isEmpty else { return nil }
        return dict[key]
    }

    /// ARPAbet (CMUdict) → eSpeak IPA, restricted to symbols present in the model
    /// vocab. AH0 is the schwa; `ɝ`→`ɚ` and `g`→`ɡ` (script-g) because the former
    /// of each pair isn't in the vocab.
    private static func mapPhone(_ raw: String) -> String? {
        if raw == "AH0" { return "ə" }
        let base = raw.filter { !$0.isNumber }       // strip stress digits
        return arpaToIPA[base]
    }

    private static let arpaToIPA: [String: String] = [
        "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ",
        "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "EH": "ɛ", "ER": "ɚ", "EY": "eɪ",
        "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "iː", "JH": "dʒ", "K": "k",
        "L": "l", "M": "m", "N": "n", "NG": "ŋ", "OW": "oʊ", "OY": "ɔɪ", "P": "p",
        "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t", "TH": "θ", "UH": "ʊ", "UW": "uː",
        "V": "v", "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ",
    ]

    /// Every IPA symbol the G2P can produce — the union of `arpaToIPA`'s values and the
    /// `ə` schwa emitted for unstressed `AH0`. This is exactly the inventory the GOP
    /// pipeline can attach to a `PhonemeScore` (expected `symbol` or `actualSymbol`),
    /// so `PhonemeAnchor` coverage can be driven off it (see `PhonemeAnchorTests`).
    public static let producibleSymbols: Set<String> = Set(arpaToIPA.values).union(["ə"])
}

#if canImport(CoreML) && canImport(AVFoundation)

// MARK: - Core ML phoneme runner

/// Loads the on-device phoneme CTC model + its vocab and turns a 16 kHz mono clip
/// into per-frame phoneme log-probabilities for `CTCForcedAligner`.
public final class PhonemeRecognizer {
    public struct Vocab {
        public let symbolToId: [String: Int]
        public let idToSymbol: [Int: String]
        public let blankId: Int
        public let frameStride: Double
    }

    private let model: MLModel
    public let vocab: Vocab
    /// The model's single static input length (samples). Every clip is padded to it;
    /// clips longer than it are chunked and their frames concatenated. A single fixed
    /// shape is what lets the GPU/ANE run the model (vs. CPU-only for dynamic shapes).
    private let buckets = [160_000]   // 10s @ 16kHz
    private let samplesPerFrame = 320   // wav2vec2: 20ms @ 16kHz

    public init?(modelURL: URL, vocabURL: URL) {
        guard let vocab = Self.loadVocab(vocabURL), let model = Self.loadModel(modelURL) else { return nil }
        self.vocab = vocab
        self.model = model
    }

    private static func loadModel(_ url: URL) -> MLModel? {
        let config = MLModelConfiguration()
        // CPU+GPU with the FP16 (un-quantized) static model. FP16 is the GPU's native
        // format, so MPSGraph compiles it (unlike the INT8 model, which failed with
        // "MLIR pass manager failed" — the GPU can't lower its dequantize ops here).
        config.computeUnits = .cpuAndGPU
        if url.pathExtension == "mlmodelc" {
            do { return try MLModel(contentsOf: url, configuration: config) }
            catch { HexLog.pronunciation.error("MLModel load failed: \(error.localizedDescription, privacy: .public)"); return nil }
        }
        // .mlpackage (e.g. side-loaded into Application Support) — compile first.
        do {
            let compiled = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled, configuration: config)
        } catch {
            HexLog.pronunciation.error("compileModel failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func loadVocab(_ url: URL) -> Vocab? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["vocab"] as? [String: String],
              let blank = json["blank_id"] as? Int else { return nil }
        var idToSymbol: [Int: String] = [:]
        var symbolToId: [String: Int] = [:]
        for (key, sym) in raw { if let id = Int(key) { idToSymbol[id] = sym; symbolToId[sym] = id } }
        let stride = (json["frame_stride_seconds"] as? Double) ?? 0.02
        return Vocab(symbolToId: symbolToId, idToSymbol: idToSymbol, blankId: blank, frameStride: stride)
    }

    /// 16 kHz mono samples → per-frame log-probabilities (frames × vocab).
    public func emissions(samples rawSamples: [Float]) throws -> [[Float]] {
        guard !rawSamples.isEmpty else { return [] }
        // wav2vec2 was trained on zero-mean / unit-variance input — normalize the
        // whole clip to match, or phoneme posteriors are degraded.
        let samples = Self.normalize(rawSamples)
        var rows: [[Float]] = []
        let maxBucket = buckets.last!
        var offset = 0
        repeat {
            let take = min(samples.count - offset, maxBucket)
            let chunk = Array(samples[offset ..< offset + take])
            let bucket = buckets.first(where: { $0 >= chunk.count }) ?? maxBucket
            var padded = chunk
            if padded.count < bucket { padded.append(contentsOf: repeatElement(0, count: bucket - padded.count)) }
            let frames = try run(padded)
            // Drop frames that only cover the zero padding.
            let realFrames = min(frames.count, max(1, Int((Double(take) / Double(samplesPerFrame)).rounded())))
            rows.append(contentsOf: frames.prefix(realFrames))
            offset += take
        } while offset < samples.count
        return rows
    }

    private static func normalize(_ samples: [Float]) -> [Float] {
        let n = Float(samples.count)
        let mean = samples.reduce(0, +) / n
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let std = (variance + 1e-7).squareRoot()
        return samples.map { ($0 - mean) / std }
    }

    private func run(_ samples: [Float]) throws -> [[Float]] {
        let array = try MLMultiArray(shape: [1, NSNumber(value: samples.count)], dataType: .float32)
        samples.withUnsafeBufferPointer { src in
            array.dataPointer.bindMemory(to: Float.self, capacity: samples.count)
                .update(from: src.baseAddress!, count: samples.count)
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["input_values": MLFeatureValue(multiArray: array)])
        let output = try model.prediction(from: input)
        guard let lp = output.featureValue(for: "log_probs")?.multiArrayValue else {
            throw PronunciationError.modelOutputMissing
        }
        let frames = lp.shape[1].intValue
        let classes = lp.shape[2].intValue
        let s1 = lp.strides[1].intValue
        let s2 = lp.strides[2].intValue
        var matrix = [[Float]](); matrix.reserveCapacity(frames)
        switch lp.dataType {
        case .float32:
            let p = lp.dataPointer.bindMemory(to: Float.self, capacity: lp.count)
            for t in 0 ..< frames {
                var row = [Float](repeating: 0, count: classes)
                for c in 0 ..< classes { row[c] = p[t * s1 + c * s2] }
                matrix.append(row)
            }
        case .float16:
            let p = lp.dataPointer.bindMemory(to: Float16.self, capacity: lp.count)
            for t in 0 ..< frames {
                var row = [Float](repeating: 0, count: classes)
                for c in 0 ..< classes { row[c] = Float(p[t * s1 + c * s2]) }
                matrix.append(row)
            }
        default:
            for t in 0 ..< frames {
                var row = [Float](repeating: 0, count: classes)
                for c in 0 ..< classes { row[c] = lp[[0, NSNumber(value: t), NSNumber(value: c)]].floatValue }
                matrix.append(row)
            }
        }
        return matrix
    }

    /// Read an audio file as 16 kHz mono float samples (the ASR / phoneme-model format).
    ///
    /// In-app notes are recorded at 16 kHz mono PCM, but the keyboard's Flow Session
    /// records `.caf` in the device-native format (commonly 48 kHz stereo). Rather than
    /// reject those, anything that isn't already 16 kHz mono is resampled / down-mixed
    /// here via `AVAudioConverter`, so pronunciation analysis works regardless of source.
    public static func loadSamples(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        // Fast path: already 16 kHz mono — read straight through.
        if format.sampleRate == 16_000, format.channelCount == 1 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData else { return [] }
            return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
        }

        // Otherwise convert to 16 kHz mono float32.
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw PronunciationError.unsupportedAudioFormat
        }

        guard file.length > 0,
              let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: source)

        let ratio = target.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount((Double(source.frameLength) * ratio).rounded(.up)) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return source
        }
        if status == .error { throw PronunciationError.unsupportedAudioFormat }

        guard let channel = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }
}

// MARK: - Analyzer

/// Ties the phoneme model + G2P + forced aligner into per-word / per-phoneme
/// pronunciation scores for a known transcript.
public final class PronunciationAnalyzer {
    private let recognizer: PhonemeRecognizer
    private let g2p: PhonemeG2P

    public init(recognizer: PhonemeRecognizer, g2p: PhonemeG2P) {
        self.recognizer = recognizer
        self.g2p = g2p
    }

    public convenience init?(modelURL: URL, vocabURL: URL, cmudictURL: URL) {
        guard let recognizer = PhonemeRecognizer(modelURL: modelURL, vocabURL: vocabURL),
              let g2p = PhonemeG2P(cmudictURL: cmudictURL) else { return nil }
        self.init(recognizer: recognizer, g2p: g2p)
    }

    public func analyze(samples: [Float], transcript: String) throws -> PronunciationResult {
        let emissions = try recognizer.emissions(samples: samples)
        guard !emissions.isEmpty else { throw PronunciationError.noAudioFrames }

        // Build the expected phoneme-id sequence from the transcript, tracking which
        // ids belong to which word. Out-of-dictionary words are skipped.
        let words = transcript.split { !$0.isLetter && $0 != "'" }.map(String.init)
        var targetIds: [Int] = []
        var symbols: [String] = []
        var ranges: [(word: String, start: Int, end: Int)] = []
        for word in words {
            guard let ipa = g2p.phonemes(for: word) else { continue }
            let ids = ipa.compactMap { recognizer.vocab.symbolToId[$0] }
            guard ids.count == ipa.count, !ids.isEmpty else { continue }
            let start = targetIds.count
            targetIds.append(contentsOf: ids)
            symbols.append(contentsOf: ipa)
            ranges.append((word, start, targetIds.count))
        }
        guard !targetIds.isEmpty else { throw PronunciationError.noRecognizableWords }
        guard targetIds.count <= emissions.count else { throw PronunciationError.clipTooShort }

        guard let spans = CTCForcedAligner.align(
            emissions: emissions,
            targets: targetIds,
            blank: recognizer.vocab.blankId,
            frameDuration: recognizer.vocab.frameStride
        ) else { throw PronunciationError.alignmentFailed }

        // Contrastive GOP per phoneme: mean over its frames of (logP(expected) − max logP).
        // Alongside it, decode the actually-pronounced sound (mode of per-frame argmax)
        // so we can show "expected /x/ → you said /y/".
        let stride = recognizer.vocab.frameStride
        let blank = recognizer.vocab.blankId
        var scores: [PhonemeScore] = []
        for (i, span) in spans.enumerated() {
            let f0 = max(0, Int((span.start / stride).rounded()))
            let f1 = min(emissions.count, max(f0 + 1, Int((span.end / stride).rounded())))
            let domId = Self.dominantClass(in: emissions, frames: f0 ..< f1, blank: blank)
            let domSym = domId.flatMap { recognizer.vocab.idToSymbol[$0] }
            // A *syllabic* realization (e.g. "-ful" → [əl], "little" → [l̩]) is correct
            // connected speech, not a substitution: the forced aligner just expects the
            // un-merged phonemes. Credit the GOP against the syllabic token and don't
            // report a swapped sound, so it isn't flagged red or counted as "unclear".
            let prev = i > 0 ? symbols[i - 1] : nil
            let next = i < symbols.count - 1 ? symbols[i + 1] : nil
            let isSyllabic = domSym.map {
                Self.isSyllabicRealization(decoded: $0, expected: symbols[i], prev: prev, next: next)
            } ?? false
            var sum = 0.0
            var n = 0
            for t in f0 ..< f1 {
                let row = emissions[t]
                var expected = Double(row[targetIds[i]])
                if isSyllabic, let domId { expected = max(expected, Double(row[domId])) }
                let best = row.max().map(Double.init) ?? expected
                sum += (expected - best)
                n += 1
            }
            scores.append(PhonemeScore(symbol: symbols[i], start: span.start, end: span.end,
                                       gop: n > 0 ? sum / Double(n) : 0,
                                       actualSymbol: isSyllabic ? symbols[i] : domSym))
        }

        let wordScores = ranges.map { WordScore(word: $0.word, phonemes: Array(scores[$0.start ..< $0.end])) }
        return PronunciationResult(words: wordScores)
    }

    /// The most frequently dominant (per-frame argmax) non-blank class over a frame
    /// range — i.e. the sound the model most often "heard" while the speaker was
    /// producing this phoneme. Returns `nil` if every in-range frame is blank-dominated
    /// or the range is empty. Pure and model-free so it's unit-testable.
    static func dominantClass(in emissions: [[Float]], frames: Range<Int>, blank: Int) -> Int? {
        var tally: [Int: Int] = [:]
        for t in frames where t >= 0 && t < emissions.count {
            let row = emissions[t]
            guard !row.isEmpty else { continue }
            var bestId = 0
            var bestVal = -Float.infinity
            for (c, v) in row.enumerated() where v > bestVal { bestVal = v; bestId = c }
            if bestId != blank { tally[bestId, default: 0] += 1 }
        }
        // Highest tally wins; ties broken deterministically toward the smaller class id.
        return tally.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key
    }

    /// Combining marks that turn a consonant into its *syllabic* form (`l` → `l̩`,
    /// `n` → `n̩`). A consonant carrying only these is the same phoneme realized as a
    /// syllable nucleus, not a different sound.
    static let syllabicMarks: Set<Unicode.Scalar> = [
        "\u{0329}", // combining vertical line below  (l̩, n̩, m̩)
        "\u{030D}", // combining vertical line above
    ]

    /// Whether `decoded` is a *syllabic realization* of the expected phoneme rather than
    /// a genuine substitution. English reduces unstressed endings to syllabic units the
    /// phoneme model has dedicated tokens for — `-ful` is syllabic `[əl]`, `little` ends
    /// in syllabic `[l̩]` — but the forced aligner still expects the un-merged `[ə][l]`,
    /// so the merged token decodes as a bogus "you said /əl/" error. Two correct shapes:
    ///   • diacritic — the same consonant with a syllabic mark (`l` → `l̩`), and
    ///   • digraph — the expected phoneme fused with an adjacent target (`ə`+`l` → `əl`).
    /// Pure and model-free so it's unit-testable.
    static func isSyllabicRealization(decoded: String, expected: String, prev: String?, next: String?) -> Bool {
        guard decoded != expected else { return false }
        // Diacritic form: strip syllabic marks and compare the base consonant.
        let base = String(String.UnicodeScalarView(decoded.unicodeScalars.filter { !syllabicMarks.contains($0) }))
        if base == expected { return true }
        // Digraph form: the expected phoneme merged with the neighbour it fused into.
        if let next, decoded == expected + next { return true }
        if let prev, decoded == prev + expected { return true }
        return false
    }
}

#endif
