import Foundation
import Testing
@testable import VocoCore

// MARK: - URLProtocol stub (no network)

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func reply(status: Int, json: String) {
        responder = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        guard let responder = StubURLProtocol.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession turns `httpBody` into a stream by the time a URLProtocol sees it.
    var capturedBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Tests

@Suite(.serialized)
struct GeminiClientTests {
    private func makeClient() -> GeminiClient { GeminiClient(session: StubURLProtocol.session()) }

    @Test
    func parsesTextAndUsage() async throws {
        StubURLProtocol.reply(status: 200, json: """
        {"candidates":[{"content":{"parts":[{"text":"Hello "},{"text":"world"}]}}],
         "usageMetadata":{"promptTokenCount":11,"candidatesTokenCount":4,"totalTokenCount":15}}
        """)
        let result = try await makeClient().generate(
            model: GeminiClient.Model.flash, apiKey: "k", parts: [.text("hi")]
        )
        #expect(result.text == "Hello world")
        #expect(result.usage == GeminiUsage(promptTokens: 11, outputTokens: 4, totalTokens: 15))
    }

    @Test
    func buildsEndpointURLForModelAndKey() async throws {
        StubURLProtocol.reply(status: 200, json: #"{"candidates":[{"content":{"parts":[{"text":"x"}]}}]}"#)
        _ = try await makeClient().generate(model: "gemini-test", apiKey: "secret123", parts: [.text("hi")])
        let url = try #require(StubURLProtocol.lastRequest?.url?.absoluteString)
        #expect(url.contains("/v1beta/models/gemini-test:generateContent"))
        #expect(url.contains("key=secret123"))
    }

    @Test
    func sendsSystemInstructionPartsAndJSONMode() async throws {
        StubURLProtocol.reply(status: 200, json: #"{"candidates":[{"content":{"parts":[{"text":"x"}]}}]}"#)
        _ = try await makeClient().generate(
            model: "m", apiKey: "k",
            parts: [.text("USER PROMPT TEXT")],
            systemInstruction: "SYSTEM ROLE", jsonResponse: true
        )
        let body = try #require(StubURLProtocol.lastRequest?.capturedBody)
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("USER PROMPT TEXT"))
        #expect(bodyString.contains("SYSTEM ROLE"))
        #expect(bodyString.contains("responseMimeType")) // JSON mode requested
    }

    @Test
    func forwardsInlineAudio() async throws {
        StubURLProtocol.reply(status: 200, json: #"{"candidates":[{"content":{"parts":[{"text":"x"}]}}]}"#)
        _ = try await makeClient().generate(
            model: "m", apiKey: "k",
            parts: [.text("t"), .inlineData(mimeType: "audio/wav", data: Data([0xDE, 0xAD]))]
        )
        let body = String(decoding: try #require(StubURLProtocol.lastRequest?.capturedBody), as: UTF8.self)
        #expect(body.contains("inlineData"))
        #expect(body.contains("audio")) // mimeType present (slash is JSON-escaped)
        #expect(body.contains(Data([0xDE, 0xAD]).base64EncodedString()))
    }

    @Test
    func nonSuccessThrowsRequestFailed() async {
        StubURLProtocol.reply(status: 400, json: #"{"error":"bad key"}"#)
        await #expect(throws: GeminiError.self) {
            _ = try await makeClient().generate(model: "m", apiKey: "k", parts: [.text("hi")])
        }
    }

    @Test
    func emptyKeyThrowsMissingAPIKeyWithoutNetwork() async {
        StubURLProtocol.responder = nil // any network use would fail
        await #expect(throws: GeminiError.missingAPIKey) {
            try await makeClient().generate(model: "m", apiKey: "", parts: [.text("hi")])
        }
    }

    @Test
    func streamYieldsDeltas() async throws {
        StubURLProtocol.reply(status: 200, json: """
        data: {"candidates":[{"content":{"parts":[{"text":"Hel"}]}}]}

        data: {"candidates":[{"content":{"parts":[{"text":"lo"}]}}]}

        data: [DONE]

        """)
        var collected = ""
        for try await delta in makeClient().stream(model: "m", apiKey: "k", parts: [.text("hi")]) {
            collected += delta
        }
        #expect(collected == "Hello")
    }
}
