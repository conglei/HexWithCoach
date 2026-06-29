import Foundation
import CryptoKit

// MARK: - Configuration

/// Hosting + integrity config for the on-device pronunciation (phoneme CTC) model.
///
/// The model is the FP16 static `PhonemeCTC.mlpackage` (~603 MB to start; a
/// palettized/base variant will shrink it later). It is delivered as a single
/// archive that the downloader streams to disk, verifies, and unpacks into the
/// sideload directory (`<Application Support>/Pronunciation/`) so runtime loading
/// is unchanged from the dev sideload path.
public struct PronunciationModelSource: Sendable, Equatable {
    /// Where the archive is hosted.
    public let url: URL
    /// Lowercase hex SHA-256 of the *downloaded archive bytes*. Verified after the
    /// streamed download completes.
    public let sha256: String
    /// Human-facing approximate download size, for the enable prompt.
    public let approximateBytes: Int64

    public init(url: URL, sha256: String, approximateBytes: Int64) {
        self.url = url
        self.sha256 = sha256
        self.approximateBytes = approximateBytes
    }

    // TODO(CI-8): hosting decision pending — releases S3 vs Hugging Face is not
    // yet decided, and this archive does not exist at the placeholder URL below.
    // Fill in the real URL and the archive's true SHA-256 before shipping the
    // download to users. Everything else in this file is real and tested.
    public static let `default` = PronunciationModelSource(
        url: URL(string: "https://voco-updates.s3.amazonaws.com/models/pronunciation/PhonemeCTC-fp16-v1.zip")!,
        // Placeholder digest — must match the hosted archive once it exists.
        sha256: "0000000000000000000000000000000000000000000000000000000000000000",
        approximateBytes: 603 * 1024 * 1024
    )
}

// MARK: - Errors

public enum PronunciationModelDownloadError: Error, LocalizedError, Equatable {
    case cancelled
    case badStatus(Int)
    case rangeNotHonored
    case checksumMismatch(expected: String, actual: String)
    case writeFailed(String)
    case missingResponse

    public var errorDescription: String? {
        switch self {
        case .cancelled: return "Download cancelled."
        case let .badStatus(code): return "Server returned status \(code)."
        case .rangeNotHonored: return "The server didn't support resuming the download."
        case .checksumMismatch: return "The downloaded model failed its integrity check."
        case let .writeFailed(reason): return "Couldn't write the model to disk: \(reason)."
        case .missingResponse: return "No response from the server."
        }
    }
}

// MARK: - Progress

public struct DownloadProgress: Sendable, Equatable {
    public let bytesReceived: Int64
    public let totalBytes: Int64?
    public init(bytesReceived: Int64, totalBytes: Int64?) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
    }
    /// 0…1 when the total is known, else nil (indeterminate).
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1.0, Double(bytesReceived) / Double(totalBytes))
    }
}

// MARK: - Downloader

/// Streaming, resumable downloader for the pronunciation model archive.
///
/// Why not `URLSession.data(for:)`: buffering a ~600 MB FP16 file in memory
/// OOM-kills on device. This streams the response bytes straight to a `.partial`
/// file on disk and only keeps a small buffer plus a rolling SHA-256 hasher in
/// memory. Interruptions leave the `.partial` file in place; the next call sends
/// an HTTP `Range` header to resume from the byte offset already on disk.
///
/// Pure download/verify/resume logic with an injectable `URLSession`, so it's
/// unit-testable against a stubbed `URLProtocol` with no real network.
public final class PronunciationModelDownloader: @unchecked Sendable {
    private let session: URLSession
    private let fileManager: FileManager

    public init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    /// Byte offset already present in a partial download for `destination`, or 0.
    public func resumeOffset(partialFor destination: URL) -> Int64 {
        let partial = Self.partialURL(for: destination)
        guard let size = try? fileManager.attributesOfItem(atPath: partial.path)[.size] as? Int64 else { return 0 }
        return size ?? 0
    }

    /// Download `source.url` to `destination`, resuming any prior `.partial` file,
    /// verifying the finished bytes against `source.sha256`, then atomically moving
    /// the verified file into place.
    ///
    /// - Parameter onProgress: called as bytes arrive (cumulative received + total).
    /// - Throws: `PronunciationModelDownloadError`.
    public func download(
        _ source: PronunciationModelSource,
        to destination: URL,
        onProgress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws {
        let partial = Self.partialURL(for: destination)
        try createParentDirectory(for: destination)

        var alreadyOnDisk = resumeOffset(partialFor: destination)

        var request = URLRequest(url: source.url)
        request.timeoutInterval = 60
        if alreadyOnDisk > 0 {
            request.setValue("bytes=\(alreadyOnDisk)-", forHTTPHeaderField: "Range")
        }

        let (byteStream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PronunciationModelDownloadError.missingResponse
        }

        // Decide whether the server honored the resume request. A 206 means it did;
        // a 200 means it's sending the whole file again (start over). Anything else
        // is an error.
        let resuming: Bool
        switch http.statusCode {
        case 206:
            resuming = alreadyOnDisk > 0
            if !resuming { throw PronunciationModelDownloadError.rangeNotHonored }
        case 200:
            // Server ignored the Range (or we had no partial): truncate and restart.
            resuming = false
            alreadyOnDisk = 0
            try? fileManager.removeItem(at: partial)
        default:
            throw PronunciationModelDownloadError.badStatus(http.statusCode)
        }

        // Total size: when resuming via 206, expectedContentLength is the remaining
        // bytes, so add what's already on disk.
        let total: Int64?
        if http.expectedContentLength > 0 {
            total = resuming ? http.expectedContentLength + alreadyOnDisk : http.expectedContentLength
        } else {
            total = source.approximateBytes > 0 ? source.approximateBytes : nil
        }

        // Open the partial file for appending (resume) or fresh writing.
        if !resuming {
            fileManager.createFile(atPath: partial.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: partial) else {
            throw PronunciationModelDownloadError.writeFailed("couldn't open \(partial.lastPathComponent)")
        }
        var didCloseHandle = false
        defer { if !didCloseHandle { try? handle.close() } }

        var hasher = SHA256()
        if resuming {
            // Re-hash the bytes already on disk so the rolling digest stays correct,
            // then append new bytes at the end.
            try seedHasher(&hasher, fromPartial: partial, upTo: alreadyOnDisk)
            try handle.seekToEnd()
        }

        var received = alreadyOnDisk
        var buffer = Data()
        buffer.reserveCapacity(Self.flushThreshold)
        onProgress?(DownloadProgress(bytesReceived: received, totalBytes: total))

        do {
            for try await byte in byteStream {
                buffer.append(byte)
                if buffer.count >= Self.flushThreshold {
                    received += Int64(buffer.count)
                    try flush(&buffer, into: handle, hasher: &hasher)
                    onProgress?(DownloadProgress(bytesReceived: received, totalBytes: total))
                }
            }
        } catch is CancellationError {
            throw PronunciationModelDownloadError.cancelled
        }

        if !buffer.isEmpty {
            received += Int64(buffer.count)
            try flush(&buffer, into: handle, hasher: &hasher)
        }
        try handle.close()
        didCloseHandle = true
        onProgress?(DownloadProgress(bytesReceived: received, totalBytes: total))

        // Integrity check on the completed archive.
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == source.sha256.lowercased() else {
            // A corrupt/mismatched archive is worthless — discard so the next attempt
            // starts clean rather than "resuming" garbage.
            try? fileManager.removeItem(at: partial)
            throw PronunciationModelDownloadError.checksumMismatch(expected: source.sha256.lowercased(), actual: digest)
        }

        // Atomically swap the verified partial into place.
        try? fileManager.removeItem(at: destination)
        do {
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            throw PronunciationModelDownloadError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Internals

    /// Flush buffered bytes to disk and fold them into the rolling hash, then clear.
    private func flush(_ buffer: inout Data, into handle: FileHandle, hasher: inout SHA256) throws {
        do {
            try handle.write(contentsOf: buffer)
        } catch {
            throw PronunciationModelDownloadError.writeFailed(error.localizedDescription)
        }
        hasher.update(data: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    /// Re-read the already-downloaded prefix in chunks to reconstruct the hash state
    /// (we can't persist a SHA256 across launches), bounded to `byteCount`.
    private func seedHasher(_ hasher: inout SHA256, fromPartial url: URL, upTo byteCount: Int64) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw PronunciationModelDownloadError.writeFailed("couldn't re-read partial for hashing")
        }
        defer { try? handle.close() }
        var remaining = byteCount
        while remaining > 0 {
            let take = Int(min(remaining, Int64(Self.flushThreshold)))
            let chunk = handle.readData(ofLength: take)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            remaining -= Int64(chunk.count)
        }
    }

    private func createParentDirectory(for url: URL) throws {
        let dir = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw PronunciationModelDownloadError.writeFailed(error.localizedDescription)
        }
    }

    static func partialURL(for destination: URL) -> URL {
        destination.appendingPathExtension("partial")
    }

    /// Flush/buffer size — small enough to keep memory flat on the big file.
    private static let flushThreshold = 1 << 20 // 1 MiB
}
