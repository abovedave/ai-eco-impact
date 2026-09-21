import Combine
import Sparkle

/// Thin ObservableObject wrapper around Sparkle's `SPUStandardUpdaterController`
/// — Sparkle's documented pattern for SwiftUI apps, which have no NIB/menu to
/// host the controller instance the way AppKit apps normally would.
final class AppUpdater: ObservableObject {
	private let controller: SPUStandardUpdaterController
	@Published private(set) var canCheckForUpdates = false

	init() {
		controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
		controller.updater.publisher(for: \.canCheckForUpdates)
			.assign(to: &$canCheckForUpdates)
	}

	func checkForUpdates() {
		controller.checkForUpdates(nil)
	}
}
