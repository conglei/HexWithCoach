import AppKit
import ComposableArchitecture
import VocoCore
import Inject
import Sparkle
import SwiftUI

@main
struct HexApp: App {
	static let appStore = Store(initialState: AppFeature.State()) {
		AppFeature()
	}

	@NSApplicationDelegateAdaptor(HexAppDelegate.self) var appDelegate

	var body: some Scene {
		// HexAppDelegate creates the menu-bar status item and the main window directly.
		// The Settings scene hosts the real tabbed settings (MC-R11): this is what the
		// standard Voco ▸ Settings… / ⌘, menu opens, and SwiftUI bridges the TabView's
		// `.tabItem`s into the native preferences toolbar. The status-bar "Settings…"
		// item routes here too via `showSettingsWindow:`.
		Settings {
			SettingsWindowView(store: HexApp.appStore)
		}
	}
}
