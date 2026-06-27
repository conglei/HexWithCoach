//
//  GeminiClient.swift
//  HexCore (Coach)
//
//  A content-agnostic transport for the Gemini Developer API (BYOK). Foundation-
//  only, no third-party SDK. (The official google-gemini/generative-ai-swift SDK
//  is deprecated; Google now points to the Firebase AI Logic SDK, which needs a
//  Firebase project + GoogleService-Info.plist and is awkward for a clean "user
//  pastes their own key" BYOK flow. Our own transport hits the REST endpoint
//  directly with the user's key.)
//
//  Lives in HexCore (rather than the HexEngine app-shared folder) so it is
//  directly covered by `swift test`: inject a stub `URLSession` to exercise
//  request building + response parsing with no network. The Coach builds the
//  prompts and parses the responses on top of it (CE-2/CE-3).
//

import Foundation
import os

public extension CoachModelTier {
    /// The default Gemini model for this tier (deep-design §6 model tiering):
    /// a cheap, audio-capable model for bulk extraction; a stronger model for
    /// verification/synthesis. Kept here (and unit-tested) rather than buried in
    /// the HexEngine adapter, whose app-shared module a test bundle can't link.
    var defaultGeminiModel: String {
        switch self {
        case .extract: return GeminiClient.Model.flashLite
        case .critic: return GeminiClient.Model.flash
        }
    }
}

/// One piece of a Gemini request: prose, or inline binary (audio/image) the model
/// should perceive directly.
public enum GeminiPart: Sendable {
    case text(String)
    case inlineData(mimeType: String, data: Data)

    fileprivate var jsonObject: [String: Any] {
        switch self {
        case let .text(text):
            return ["text": text]
        case let .inlineData(mimeType, data):
            return ["inlineData": ["mimeType": mimeType, "data": data.base64EncodedString()]]
        }
    }
}

/// Token accounting returned by the API, so callers can surface running cost
/// (CE-5) without guessing.
public struct GeminiUsage: Sendable, Equatable {
    public var promptTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public struct GeminiResult: Sendable {
    public var text: String
    public var usage: GeminiUsage?

    public init(text: String, usage: GeminiUsage?) {
        self.text = text
        self.usage = usage
    }
}

public enum GeminiError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case requestFailed(statusCode: Int, body: String)
    case invalidResponse(raw: String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Gemini API key. Add one in Settings to enable the Coach."
        case let .requestFailed(statusCode, body):
            return "Gemini request failed (\(statusCode)): \(body)"
        case .invalidResponse:
            return "Couldn't read the Gemini response."
        case .emptyResponse:
            return "The model returned an empty response."
        }
    }
}

/// Stateless transport. Construct once (cheap) and call per request; the BYOK key
/// is passed in rather than stored here.
public struct GeminiClient: Sendable {
    /// Curated default models. The Coach picks a tier per call (CE-1 model tiering).
    public enum Model {
        /// Cheap, fast — bulk extraction / objective passes.
        public static let flashLite = "gemini-2.5-flash-lite"
        /// Stronger — verification/critic passes where quality matters.
        public static let flash = "gemini-2.5-flash"
    }

    private static let host = "generativelanguage.googleapis.com"
    private let log = HexLog.coach
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Non-streaming

    /// Send `parts` to `model` and return the full text response.
    /// - Parameters:
    ///   - systemInstruction: optional system prompt (role/voice/constraints).
    ///   - jsonResponse: when true, asks the model for `application/json` so the
    ///     reply is a parseable object rather than prose/markdown.
    public func generate(
        model: String,
        apiKey: String,
        parts: [GeminiPart],
        systemInstruction: String? = nil,
        temperature: Double = 0.2,
        jsonResponse: Bool = false
    ) async throws -> GeminiResult {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }
        let request = try buildRequest(
            model: model, apiKey: apiKey, parts: parts,
            systemInstruction: systemInstruction, temperature: temperature,
            jsonResponse: jsonResponse, streaming: false
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(statusCode: -1, body: "no HTTP response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            log.error("Gemini request failed: \(http.statusCode, privacy: .public)")
            throw GeminiError.requestFailed(statusCode: http.statusCode, body: body)
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        let text = try Self.extractText(from: data, raw: raw)
        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        return GeminiResult(text: text, usage: Self.extractUsage(from: data))
    }

    // MARK: - Streaming

    /// Stream text deltas as the model responds (SSE). The terminal value is the
    /// concatenation of every yielded delta.
    public func stream(
        model: String,
        apiKey: String,
        parts: [GeminiPart],
        systemInstruction: String? = nil,
        temperature: Double = 0.2,
        jsonResponse: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task<Void, Never> {
                do {
                    guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }
                    let request = try buildRequest(
                        model: model, apiKey: apiKey, parts: parts,
                        systemInstruction: systemInstruction, temperature: temperature,
                        jsonResponse: jsonResponse, streaming: true
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw GeminiError.requestFailed(statusCode: -1, body: "no HTTP response")
                    }
                    guard (200 ... 299).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n" }
                        throw GeminiError.requestFailed(statusCode: http.statusCode, body: body)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst("data: ".count))
                        if payload == "[DONE]" { break }
                        guard let chunk = payload.data(using: .utf8),
                              let delta = Self.extractDelta(from: chunk), !delta.isEmpty
                        else { continue }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    private func buildRequest(
        model: String,
        apiKey: String,
        parts: [GeminiPart],
        systemInstruction: String?,
        temperature: Double,
        jsonResponse: Bool,
        streaming: Bool
    ) throws -> URLRequest {
        var generationConfig: [String: Any] = ["temperature": temperature]
        if jsonResponse { generationConfig["responseMimeType"] = "application/json" }

        var body: [String: Any] = [
            "contents": [["role": "user", "parts": parts.map(\.jsonObject)]],
            "generationConfig": generationConfig,
        ]
        if let systemInstruction, !systemInstruction.isEmpty {
            body["system_instruction"] = ["parts": [["text": systemInstruction]]]
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        let method = streaming ? "streamGenerateContent" : "generateContent"
        components.path = "/v1beta/models/\(model):\(method)"
        var query = [URLQueryItem(name: "key", value: apiKey)]
        if streaming { query.append(URLQueryItem(name: "alt", value: "sse")) }
        components.queryItems = query

        guard let url = components.url else {
            throw GeminiError.requestFailed(statusCode: -1, body: "bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response parsing

    private static func extractText(from data: Data, raw: String) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.invalidResponse(raw: raw)
        }
        guard let text = candidateText(from: root) else {
            throw GeminiError.invalidResponse(raw: raw)
        }
        return text
    }

    private static func extractDelta(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return candidateText(from: root)
    }

    /// Pull `candidates[0].content.parts[*].text`, joined.
    private static func candidateText(from root: [String: Any]) -> String? {
        guard let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return nil }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    private static func extractUsage(from data: Data) -> GeminiUsage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usageMetadata"] as? [String: Any]
        else { return nil }
        let prompt = usage["promptTokenCount"] as? Int ?? 0
        let output = usage["candidatesTokenCount"] as? Int ?? 0
        let total = usage["totalTokenCount"] as? Int ?? (prompt + output)
        return GeminiUsage(promptTokens: prompt, outputTokens: output, totalTokens: total)
    }
}
