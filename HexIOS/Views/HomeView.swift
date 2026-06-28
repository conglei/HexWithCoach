//
//  HomeView.swift
//  HexIOS
//
//  Home tab. A greeting + a big gradient mic for in-app capture, a dictation
//  status pill, and a Recent preview. Styled with the shared HexTheme.
//

import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    let model: DictationModel
    @Binding var selectedTab: AppTab
    let onShowAllHistory: () -> Void
    @Query(sort: \TranscriptEntry.date, order: .reverse) private var entries: [TranscriptEntry]
    @State private var incognito = CapturePreferences.incognito
    @State private var path = NavigationPath()

    // Pull-down-to-dictate.
    @State private var pull: CGFloat = 0
    @State private var pullArmed = false
    private let pullThreshold: CGFloat = 110

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ScrollView {
                    ZStack(alignment: .top) {
                        // Scroll-offset probe (drives pull-to-dictate).
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .named("home")).minY
                            )
                        }
                        .frame(height: 0)

                        VStack(alignment: .leading, spacing: 0) {
                            header.padding(.top, 8)
                            statusView
                            Spacer(minLength: 24)
                            hero
                            Spacer(minLength: 0).frame(height: 32)
                            if !entries.isEmpty { recentSection }
                        }
                        .frame(minHeight: geo.size.height, alignment: .top)
                        .padding(.horizontal, 20)
                    }
                }
                .coordinateSpace(name: "home")
                .scrollIndicators(.hidden)
                // The content is exactly one screen tall, so without forcing bounce
                // the ScrollView can't overscroll and pull-to-dictate never fires.
                // `.always` lets it rubber-band even when content fits.
                .scrollBounceBehavior(.always)
                // Prefer the reliable iOS 18 scroll-geometry reporter; fall back to
                // the GeometryReader-preference probe on iOS 17.
                .modifier(PullDetect(onPull: handlePull))
                .overlay(alignment: .top) { pullIndicator }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TranscriptEntry.self) { TranscriptDetailView(entry: $0) }
            .fullScreenCover(isPresented: Binding(
                get: { model.phase != .idle },
                set: { presented in
                    if !presented, model.phase == .recording || model.phase == .paused {
                        model.cancelRecording()
                    }
                }
            )) {
                RecordingView(model: model)
            }
            .onAppear { incognito = CapturePreferences.incognito }
            // After an in-app note finishes recording, open it automatically.
            .onChange(of: model.lastSavedNote) { _, note in
                if let note {
                    path.append(note)
                    model.lastSavedNote = nil
                }
            }
        }
    }

    // MARK: - Pull to dictate

    /// Pulling the screen down past the threshold and releasing starts a new note
    /// — the second way to dictate, alongside tapping the mic.
    private func handlePull(_ offset: CGFloat) {
        let amount = max(0, offset)
        pull = amount
        if amount >= pullThreshold {
            if !pullArmed {
                pullArmed = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else if pullArmed, amount < pullThreshold * 0.6 {
            // Released past the threshold → start dictating.
            pullArmed = false
            if model.canRecord { Task { await model.toggleRecording() } }
        }
    }

    @ViewBuilder
    private var pullIndicator: some View {
        if pull > 1, model.phase == .idle {
            let progress = min(1, pull / pullThreshold)
            VStack(spacing: 6) {
                Image(systemName: pullArmed ? "mic.fill" : "arrow.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(HexTheme.gradient, in: .circle)
                    .scaleEffect(0.7 + 0.3 * progress)
                Text(pullArmed ? "Release to dictate" : "Pull to dictate")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .opacity(Double(min(1, pull / 50)))
            .offset(y: min(pull, pullThreshold) * 0.5 - 8)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: pullArmed)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let status = statusLine {
            Text(status.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(status.accent ? AnyShapeStyle(HexTheme.gradientColors[0]) : AnyShapeStyle(.secondary))
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.subheadline).foregroundStyle(.secondary)
                Text("Hex").font(.largeTitle.weight(.bold))
            }
            Spacer()
            HStack(spacing: 8) {
                incognitoButton
                dictationPill
            }
            .padding(.top, 6)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5 ..< 12: "Good morning"
        case 12 ..< 17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var dictationPill: some View {
        Button {
            if model.sessionActive { model.endSession() } else { Task { await model.startKeyboardSession() } }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(model.sessionActive ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(model.sessionActive ? "Dictation on" : "Dictation off")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(model.modelState != .ready)
        .opacity(model.modelState == .ready ? 1 : 0.5)
    }

    private var incognitoButton: some View {
        Button {
            incognito.toggle()
            CapturePreferences.incognito = incognito
        } label: {
            Image(systemName: "eyeglasses")
                .font(.subheadline)
                .foregroundStyle(incognito ? AnyShapeStyle(HexTheme.gradientColors[0]) : AnyShapeStyle(.secondary))
                .frame(width: 34, height: 34)
                .background(
                    incognito ? AnyShapeStyle(HexTheme.gradientSoft) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(incognito ? "Incognito on" : "Incognito off")
    }

    private var statusLine: (text: String, accent: Bool)? {
        if incognito { return ("Incognito — dictation won’t be saved", true) }
        switch model.modelState {
        case .loading:
            return (model.modelProgress > 0
                ? "Downloading model… \(Int(model.modelProgress * 100))%"
                : "Preparing model… first run downloads ~600MB", false)
        case .failed: return ("Model unavailable", false)
        case .ready: return nil
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 18) {
            GradientMicButton(systemImage: micSymbol, size: 140) {
                Task { await model.toggleRecording() }
            }
            .disabled(!model.canRecord && model.phase != .recording)
            .opacity(model.canRecord || model.phase == .recording ? 1 : 0.5)

            VStack(spacing: 4) {
                Text("Tap to dictate").font(.title2.weight(.semibold))
                Text(captionText).font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var micSymbol: String {
        switch model.phase {
        case .idle: "mic.fill"
        case .recording: "stop.fill"
        case .paused: "mic.fill"
        case .transcribing: "ellipsis"
        }
    }

    private var captionText: String {
        switch model.phase {
        case .idle: "Records and saves a note here"
        case .recording: "Listening… tap to stop"
        case .paused: "Paused"
        case .transcribing: "Transcribing…"
        }
    }

    // MARK: - Recent

    private var recentEntries: [TranscriptEntry] { Array(entries.prefix(3)) }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("See all") { onShowAllHistory() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HexTheme.gradientColors[0])
            }

            ForEach(recentEntries, id: \.persistentModelID) { entry in
                NavigationLink(value: entry) { recentCard(entry) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 24)
    }

    private func recentCard(_ entry: TranscriptEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .font(.subheadline)
                .foregroundStyle(HexTheme.gradientColors[0])
                .frame(width: 36, height: 36)
                .background(HexTheme.gradientSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(entry.text)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .hexCard(padding: 12)
    }
}

/// Reports the Home content's top offset within the scroll view so the pull-down
/// gesture can detect an overscroll (iOS 17 fallback path).
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Reports pull-down overscroll amount (positive when dragging below the top).
/// iOS 18's `onScrollGeometryChange` reports the true content offset even during a
/// rubber-band, which the GeometryReader-preference probe misses when the content
/// exactly fits the screen. Falls back to that probe on iOS 17.
private struct PullDetect: ViewModifier {
    let onPull: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                // At rest (scrolled to top) contentOffset.y == -contentInsets.top;
                // pulling down makes it more negative, so this is the overscroll.
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, amount in
                onPull(amount)
            }
        } else {
            content.onPreferenceChange(ScrollOffsetKey.self) { onPull($0) }
        }
    }
}
