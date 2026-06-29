import ComposableArchitecture
import VocoCore
import SwiftUI

private let appLogger = HexLog.app
private let cacheLogger = HexLog.caches

class HexAppDelegate: NSObject, NSApplicationDelegate {
	var invisibleWindow: InvisibleWindow?
	var settingsWindow: NSWindow?
	var statusItem: NSStatusItem!
	private var launchedAtLogin = false

	@Dependency(\.soundEffects) var soundEffect
	@Dependency(\.recording) var recording
	@Shared(.hexSettings) var hexSettings: HexSettings
	@Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory

	func applicationDidFinishLaunching(_: Notification) {
		DiagnosticsLogging.bootstrapIfNeeded()
		// Ensure Parakeet/FluidAudio caches live under Application Support, not ~/.cache
		configureLocalCaches()
		if isTesting {
			appLogger.debug("Running in testing mode")
			return
		}

		Task {
			await soundEffect.preloadSounds()
			await soundEffect.setEnabled(hexSettings.soundEffectsEnabled)
		}
		// Stand up the shared SwiftData store (MC-R3) and hydrate the TCA history
		// projection from it, so History reads/writes flow through the synced store.
		// This also stands up the Coach v2 driver (MC-R4) over the shared context.
		MacTranscriptStore.shared.bootstrapAndHydrate(into: $transcriptionHistory)

		// Coach v2 launch passes (MC-R4): backfill the keyless objective lane across
		// any pre-existing notes, then (if opted in with a key + under budget) run an
		// auto-batched LLM pass over the backlog. Best-effort; never blocks launch.
		if let coach = MacTranscriptStore.shared.coach {
			Task { @MainActor in await coach.runLaunchPasses() }
		}

		launchedAtLogin = wasLaunchedAtLogin()
		appLogger.info("Application did finish launching")
		appLogger.notice("launchedAtLogin = \(self.launchedAtLogin)")

		// Set activation policy first
		updateAppMode()

		// Add notification observers
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAppModeUpdate),
			name: .updateAppMode,
			object: nil
		)

		// Status bar UI (replaces SwiftUI MenuBarExtra)
		setupStatusItemAndPopover()

		// Start long-running app effects (global hotkeys, permissions, etc.)
		startLifecycleTasksIfNeeded()

		// Then present main views
		presentMainView()

		guard shouldOpenForegroundUIOnLaunch else {
			appLogger.notice("Suppressing foreground windows for login launch")
			return
		}

		presentSettingsView()
		NSApp.activate(ignoringOtherApps: true)
	}

	private var shouldOpenForegroundUIOnLaunch: Bool {
		!launchedAtLogin
	}

	private func wasLaunchedAtLogin() -> Bool {
		guard let event = NSAppleEventManager.shared().currentAppleEvent else {
			return false
		}

		return event.eventID == AEEventID(kAEOpenApplication)
			&& event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEEventClass(keyAELaunchedAsLogInItem)
	}

	private func startLifecycleTasksIfNeeded() {
		Task { @MainActor in
			await HexApp.appStore.send(.task).finish()
		}
	}

	private func configureLocalCaches() {
		do {
			let cache = try URL.hexApplicationSupport.appendingPathComponent("cache", isDirectory: true)
			try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
			setenv("XDG_CACHE_HOME", cache.path, 1)
			cacheLogger.info("XDG_CACHE_HOME set to \(cache.path)")
		} catch {
			cacheLogger.error("Failed to configure local caches: \(error.localizedDescription)")
		}
	}

	// MARK: - Status item + popover

	private func setupStatusItemAndPopover() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = statusItem.button {
			button.target = self
			button.action = #selector(statusItemClicked(_:))
			button.sendAction(on: [.leftMouseUp, .rightMouseUp])
			refreshStatusIcon(on: button)
		}
	}

	private func refreshStatusIcon(on button: NSStatusBarButton) {
		guard let base = NSImage(named: "VocoLogo") else { return }
		button.image = scaledMenuBarImage(base, target: 18)
	}

	private func scaledMenuBarImage(_ image: NSImage, target: CGFloat) -> NSImage {
		let copy = NSImage(size: image.size)
		copy.addRepresentations(image.representations)
		let ratio = copy.size.height / max(copy.size.width, 1)
		copy.size = NSSize(width: target / ratio, height: target)
		copy.isTemplate = true
		return copy
	}

	@objc private func statusItemClicked(_ sender: Any?) {
		let event = NSApp.currentEvent
		let isRightClick = event?.type == .rightMouseUp
			|| (event?.modifierFlags.contains(.control) ?? false)

		if isRightClick {
			showStatusMenu()
		} else {
			// Left-click opens Settings now that the legacy coach popover is gone (MC-R4).
			presentSettingsView()
		}
	}

	private func showStatusMenu() {
		let menu = NSMenu()

		let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(menuCheckForUpdates(_:)), keyEquivalent: "")
		checkUpdates.target = self
		menu.addItem(checkUpdates)

		let copyLast = NSMenuItem(title: "Copy Last Transcript", action: #selector(menuCopyLastTranscript(_:)), keyEquivalent: "")
		copyLast.target = self
		menu.addItem(copyLast)

		menu.addItem(.separator())

		let settings = NSMenuItem(title: "Settings…", action: #selector(menuOpenSettings(_:)), keyEquivalent: ",")
		settings.target = self
		menu.addItem(settings)

		menu.addItem(.separator())

		let quit = NSMenuItem(title: "Quit", action: #selector(menuQuit(_:)), keyEquivalent: "q")
		quit.target = self
		menu.addItem(quit)

		statusItem.menu = menu
		statusItem.button?.performClick(nil)
		// Detach menu so future left-clicks don't open it.
		statusItem.menu = nil
	}

	@objc private func menuCheckForUpdates(_ sender: Any?) {
		Task { @MainActor in
			CheckForUpdatesViewModel.shared.checkForUpdates()
		}
	}

	@objc private func menuCopyLastTranscript(_ sender: Any?) {
		Task { @MainActor in
			await HexApp.appStore.send(.pasteLastTranscript).finish()
		}
	}

	@objc private func menuOpenSettings(_ sender: Any?) {
		presentSettingsView()
	}

	@objc private func menuQuit(_ sender: Any?) {
		NSApp.terminate(nil)
	}

	// MARK: - Windows

	func presentMainView() {
		guard invisibleWindow == nil else {
			return
		}
		let transcriptionStore = HexApp.appStore.scope(state: \.transcription, action: \.transcription)
		let transcriptionView = TranscriptionView(store: transcriptionStore).padding().padding(.top).padding(.top)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		invisibleWindow = InvisibleWindow.fromView(transcriptionView)
		invisibleWindow?.orderFrontRegardless()
	}

	func presentSettingsView() {
		if let settingsWindow = settingsWindow {
			settingsWindow.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let settingsView = AppView(store: HexApp.appStore)
		let settingsWindow = NSWindow(
			contentRect: .init(x: 0, y: 0, width: 700, height: 700),
			styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		settingsWindow.titleVisibility = .visible
		settingsWindow.contentView = NSHostingView(rootView: settingsView)
		settingsWindow.isReleasedWhenClosed = false
		settingsWindow.minSize = .init(width: 620, height: 560)
		settingsWindow.setFrameAutosaveName("Settings")
		settingsWindow.center()
		settingsWindow.toolbarStyle = NSWindow.ToolbarStyle.unified
		settingsWindow.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.settingsWindow = settingsWindow
	}

	@objc private func handleAppModeUpdate() {
		Task {
			await updateAppMode()
		}
	}

	@MainActor
	private func updateAppMode() {
		appLogger.debug("showDockIcon = \(self.hexSettings.showDockIcon)")
		if self.hexSettings.showDockIcon {
			NSApp.setActivationPolicy(.regular)
		} else {
			NSApp.setActivationPolicy(.accessory)
		}
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		presentSettingsView()
		return true
	}

	func applicationWillTerminate(_: Notification) {
		Task {
			await recording.cleanup()
		}
	}
}
