import CryptoKit
import Foundation
import Testing
@testable import HexCore

// MARK: - URLProtocol stub (no network)

/// Serves a fixed payload, honoring a `Range: bytes=N-` request with a 206 + the
/// remaining bytes (so resume can be exercised). The responder can also force a
/// 200 to simulate a server that ignores Range, or a non-2xx error.
private final class DownloadStubProtocol: URLProtocol, @unchecked Sendable {
    enum Mode {
        case serve(Data)        // full file, honoring Range with 206
        case ignoreRange(Data)  // always 200 with the full file
        case status(Int)        // error status
    }

    nonisolated(unsafe) static var mode: Mode = .status(500)
    nonisolated(unsafe) static var capturedRangeHeaders: [String?] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DownloadStubProtocol.self]
        return URLSession(configuration: config)
    }

    static func reset(_ mode: Mode) {
        self.mode = mode
        capturedRangeHeaders = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let rangeHeader = request.value(forHTTPHeaderField: "Range")
        DownloadStubProtocol.capturedRangeHeaders.append(rangeHeader)
        let url = request.url!

        func send(status: Int, body: Data, headers: [String: String]) {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        }

        switch DownloadStubProtocol.mode {
        case let .serve(data):
            if let rangeHeader, let offset = Self.parseRangeStart(rangeHeader), offset > 0, offset < data.count {
                let remaining = data.subdata(in: offset ..< data.count)
                send(status: 206, body: remaining, headers: ["Content-Length": "\(remaining.count)"])
            } else {
                send(status: 200, body: data, headers: ["Content-Length": "\(data.count)"])
            }
        case let .ignoreRange(data):
            send(status: 200, body: data, headers: ["Content-Length": "\(data.count)"])
        case let .status(code):
            send(status: code, body: Data(), headers: [:])
        }
    }

    override func stopLoading() {}

    private static func parseRangeStart(_ header: String) -> Int? {
        // "bytes=123-"
        guard let eq = header.firstIndex(of: "="), let dash = header.firstIndex(of: "-") else { return nil }
        let start = header[header.index(after: eq) ..< dash]
        return Int(start)
    }
}

// MARK: - Helpers

/// Thread-safe sink for the `@Sendable` progress callback.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DownloadProgress] = []
    func record(_ p: DownloadProgress) { lock.lock(); items.append(p); lock.unlock() }
    var last: DownloadProgress? { lock.lock(); defer { lock.unlock() }; return items.last }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func makeTempDestination() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ci8-download-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("PhonemeCTC.mlpackage")
}

private func payload(_ byteCount: Int) -> Data {
    var data = Data(capacity: byteCount)
    for i in 0 ..< byteCount { data.append(UInt8(i % 251)) }
    return data
}

// MARK: - Tests

@Suite(.serialized)
struct PronunciationModelDownloaderTests {
    private func makeDownloader() -> PronunciationModelDownloader {
        PronunciationModelDownloader(session: DownloadStubProtocol.session())
    }

    private func source(_ url: URL, sha: String, size: Int64) -> PronunciationModelSource {
        PronunciationModelSource(url: url, sha256: sha, approximateBytes: size)
    }

    @Test
    func successDownloadsVerifiesAndMovesIntoPlace() async throws {
        let bytes = payload(3 * (1 << 20) + 777) // spans multiple 1 MiB flushes
        DownloadStubProtocol.reset(.serve(bytes))
        let dest = makeTempDestination()
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }

        let collector = ProgressCollector()
        let src = source(URL(string: "https://example.com/model.zip")!, sha: sha256Hex(bytes), size: Int64(bytes.count))
        try await makeDownloader().download(src, to: dest) { collector.record($0) }

        let onDisk = try Data(contentsOf: dest)
        #expect(onDisk == bytes)
        #expect(!FileManager.default.fileExists(atPath: PronunciationModelDownloader.partialURL(for: dest).path))
        let last = collector.last
        #expect(last?.bytesReceived == Int64(bytes.count))
        #expect(last?.fraction == 1.0)
    }

    @Test
    func checksumMismatchFailsAndDiscardsPartial() async throws {
        let bytes = payload(64 * 1024)
        DownloadStubProtocol.reset(.serve(bytes))
        let dest = makeTempDestination()
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }

        let wrong = String(repeating: "a", count: 64)
        let src = source(URL(string: "https://example.com/model.zip")!, sha: wrong, size: Int64(bytes.count))

        await #expect(throws: PronunciationModelDownloadError.self) {
            try await makeDownloader().download(src, to: dest)
        }
        // Both the partial and the destination must be absent after a failed verify.
        #expect(!FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: PronunciationModelDownloader.partialURL(for: dest).path))
    }

    @Test
    func resumeSendsRangeAndAppendsRemainingBytes() async throws {
        let bytes = payload(200 * 1024)
        let dest = makeTempDestination()
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }

        // Seed a partial file with the first 80 KiB already on disk.
        let prefixLength = 80 * 1024
        let partial = PronunciationModelDownloader.partialURL(for: dest)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.prefix(prefixLength).write(to: partial)

        let downloader = makeDownloader()
        #expect(downloader.resumeOffset(partialFor: dest) == Int64(prefixLength))

        DownloadStubProtocol.reset(.serve(bytes))
        let src = source(URL(string: "https://example.com/model.zip")!, sha: sha256Hex(bytes), size: Int64(bytes.count))
        try await downloader.download(src, to: dest)

        // The request must have carried a Range header at the partial's offset…
        #expect(DownloadStubProtocol.capturedRangeHeaders.first ?? nil == "bytes=\(prefixLength)-")
        // …and the reassembled file (prefix on disk + remaining from 206) must match.
        let onDisk = try Data(contentsOf: dest)
        #expect(onDisk == bytes)
    }

    @Test
    func serverIgnoringRangeRestartsAndStillSucceeds() async throws {
        let bytes = payload(120 * 1024)
        let dest = makeTempDestination()
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }

        // Partial present, but the server ignores Range (200 with the whole file).
        let partial = PronunciationModelDownloader.partialURL(for: dest)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.prefix(40 * 1024).write(to: partial)

        DownloadStubProtocol.reset(.ignoreRange(bytes))
        let src = source(URL(string: "https://example.com/model.zip")!, sha: sha256Hex(bytes), size: Int64(bytes.count))
        try await makeDownloader().download(src, to: dest)

        let onDisk = try Data(contentsOf: dest)
        #expect(onDisk == bytes) // no doubled prefix — restart truncated cleanly
    }

    @Test
    func badStatusThrows() async throws {
        DownloadStubProtocol.reset(.status(404))
        let dest = makeTempDestination()
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
        let src = source(URL(string: "https://example.com/model.zip")!, sha: String(repeating: "0", count: 64), size: 1)

        await #expect(throws: PronunciationModelDownloadError.badStatus(404)) {
            try await makeDownloader().download(src, to: dest)
        }
    }

    @Test
    func defaultSourceCarriesPlaceholderTODO() {
        // Guards that the placeholder constant exists and is obviously not-yet-real.
        #expect(PronunciationModelSource.default.sha256 == String(repeating: "0", count: 64))
        #expect(PronunciationModelSource.default.approximateBytes > 0)
    }
}
