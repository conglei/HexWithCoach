//
//  HexWidgets.swift
//  HexWidgets
//
//  Home Screen widget: one tap to start dictation, a live "keyboard on / needs
//  setup" status, and (medium) a glance at the review streak. Tapping deep-links
//  into the app — to start a Flow Session when the keyboard is ready, or to the
//  enable-keyboard flow when it isn't.
//

import AppIntents
import VocoCore
import SwiftUI
import WidgetKit

struct VocoEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeWidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> VocoEntry {
        VocoEntry(date: Date(), snapshot: HomeWidgetSnapshot(keyboardReady: true, streak: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (VocoEntry) -> Void) {
        completion(VocoEntry(date: Date(), snapshot: .current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VocoEntry>) -> Void) {
        let entry = VocoEntry(date: Date(), snapshot: .current())
        // The app reloads this widget on the events that matter (keyboard becomes
        // active, streak changes); this periodic refresh is just a safety net.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

private struct MicBadge: View {
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(.tint))
    }
}

private struct StatusPill: View {
    let ready: Bool

    var body: some View {
        Label {
            Text(ready ? "Keyboard on" : "Enable keyboard")
        } icon: {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(ready ? Color.green : Color.orange)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct StreakGlance: View {
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(streak)", systemImage: "flame.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .labelStyle(.titleAndIcon)
                .imageScale(.medium)
            Text("day streak")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// The two-zone column shared by both widget sizes: a big tap target that starts a
/// new in-app note, and a smaller one (the status pill) that opens iOS keyboard
/// settings to turn the keyboard on or off. Two separate `Button(intent:)` controls
/// give two independent tap targets even in the small widget.
struct HexWidgetsColumn: View {
    let snapshot: HomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(intent: RecordNoteIntent()) {
                VStack(alignment: .leading, spacing: 8) {
                    MicBadge()
                    Text("Start dictation")
                        .font(.headline)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(intent: ManageKeyboardIntent()) {
                StatusPill(ready: snapshot.keyboardReady)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct HexWidgetsSmallView: View {
    let snapshot: HomeWidgetSnapshot

    var body: some View {
        HexWidgetsColumn(snapshot: snapshot)
    }
}

struct HexWidgetsMediumView: View {
    let snapshot: HomeWidgetSnapshot

    var body: some View {
        HStack(spacing: 0) {
            HexWidgetsColumn(snapshot: snapshot)

            Divider()

            VStack(alignment: .leading) {
                StreakGlance(streak: snapshot.streak)
                Spacer()
            }
            .frame(width: 96, alignment: .leading)
            .padding(.leading, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct HexWidgetsEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                HexWidgetsMediumView(snapshot: entry.snapshot)
            default:
                HexWidgetsSmallView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HexWidgets: Widget {
    let kind: String = "HexWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HexWidgetsEntryView(entry: entry)
                .tint(.accentColor)
        }
        .configurationDisplayName("Dictation")
        .description("Start dictating with one tap, and keep an eye on your streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    HexWidgets()
} timeline: {
    VocoEntry(date: .now, snapshot: HomeWidgetSnapshot(keyboardReady: true, streak: 5))
    VocoEntry(date: .now, snapshot: HomeWidgetSnapshot(keyboardReady: false, streak: 0))
}

#Preview(as: .systemMedium) {
    HexWidgets()
} timeline: {
    VocoEntry(date: .now, snapshot: HomeWidgetSnapshot(keyboardReady: true, streak: 5))
}
