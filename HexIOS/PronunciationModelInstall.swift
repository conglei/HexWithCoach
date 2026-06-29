//
//  PronunciationModelInstall.swift
//  HexIOS
//
//  CI-8: download-on-demand delivery for the on-device pronunciation model.
//
//  The objective coach (pronunciation GOP + fluency) is the keyless tier (ADR-0002)
//  and needs the ~600 MB phoneme model on device — but no API key. Fluency coaching
//  works without it, so this is an opt-in enable, never a gate. This @Observable
//  drives the Settings "Enable pronunciation coaching" row: it streams the model to
//  the sideload directory (HexCore.PronunciationModelLocation) via the resumable
//  PronunciationModelDownloader, reports progress, and supports cancel.
//

import Foundation
import HexCore
import Observation
import os

@MainActor
@Observable
final class PronunciationModelInstall {
    enum Phase: Equatable {
        case unknown
        case notInstalled
        case downloading(fraction: Double?, received: Int64, total: Int64?)
        case installed
        case failed(String)
    }

    private(set) var phase: Phase = .unknown

    private let source: PronunciationModelSource
    private let downloader: PronunciationModelDownloader
    private var task: Task<Void, Never>?

    init(
        source: PronunciationModelSource = .default,
        downloader: PronunciationModelDownloader = PronunciationModelDownloader()
    ) {
        self.source = source
        self.downloader = downloader
    }

    /// Approximate download size for the prompt copy (e.g. "~600 MB").
    var approximateSizeText: String {
        let mb = Double(source.approximateBytes) / (1024 * 1024)
        return mb >= 1000
            ? String(format: "~%.1f GB", mb / 1024)
            : String(format: "~%.0f MB", mb)
    }

    var isDownloading: Bool {
        if case .downloading = phase { return true }
        return false
    }

    /// Reflect the on-disk state (downloaded or sideloaded) into `phase`.
    func refresh() {
        guard !isDownloading else { return }
        phase = PronunciationModelLocation.isInstalled() ? .installed : .notInstalled
    }

    /// Start (or resume) the streaming download into the sideload directory.
    func start() {
        guard !isDownloading else { return }
        phase = .downloading(fraction: nil, received: 0, total: source.approximateBytes)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let destination = try PronunciationModelLocation.modelURL()
                try await downloader.download(source, to: destination) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.isDownloading else { return }
                        self.phase = .downloading(
                            fraction: progress.fraction,
                            received: progress.bytesReceived,
                            total: progress.totalBytes
                        )
                    }
                }
                if !Task.isCancelled {
                    HexLog.pronunciation.info("Pronunciation model downloaded + verified")
                    phase = .installed
                }
            } catch is CancellationError {
                refresh()
            } catch let error as PronunciationModelDownloadError {
                if case .cancelled = error {
                    refresh()
                } else {
                    HexLog.pronunciation.error("Model download failed: \(error.localizedDescription, privacy: .public)")
                    phase = .failed(error.localizedDescription)
                }
            } catch {
                HexLog.pronunciation.error("Model download failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Cancel an in-flight download. The partial file stays on disk so the next
    /// `start()` resumes from where it left off.
    func cancel() {
        task?.cancel()
        task = nil
        refresh()
    }
}
