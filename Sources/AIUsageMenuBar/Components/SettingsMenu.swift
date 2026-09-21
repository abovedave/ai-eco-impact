import ServiceManagement
import SwiftUI

/// The kebab menu in the nav row: attribution links, login item, and quit.
/// Replaces the old always-visible `FooterView` and a separate quit button
/// with a single overflow menu.
struct SettingsMenu: View {
	@ObservedObject var appUpdater: AppUpdater
	let onQuit: () -> Void
	// Applied to the `Menu` itself, not inside its label: a `Menu`'s label
	// on macOS renders through a native menu-button cell that drops custom
	// SwiftUI backgrounds nested inside it (unlike a plain `Button`, whose
	// background works fine directly inside its own label).
	@State private var isHovering = false

	private var appVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
	}

	/// Read/written directly against `SMAppService` rather than cached in
	/// `@State`, since the user can also toggle this in System Settings.
	private var openAtLogin: Binding<Bool> {
		Binding(
			get: { SMAppService.mainApp.status == .enabled },
			set: { isEnabled in
				try? isEnabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
			}
		)
	}

	var body: some View {
		Menu {
			Toggle("Open at Login", isOn: openAtLogin)
			Button("Check for Updates…", action: appUpdater.checkForUpdates)
				.disabled(!appUpdater.canCheckForUpdates)
			Button("Quit", systemImage: "xmark", action: onQuit)

            Divider()

            Link(destination: URL(string: "https://github.com/abovedave/ai-eco-impact")!) {
                Text("View source on GitHub")
                Text("Version \(appVersion)")
            }

            Divider()

            Link(destination: URL(string: "https://ccusage.com")!) {
                Text("Local AI usage data")
                Text("ccusage.com")
            }
            Link(destination: URL(string: "https://calculator.ecologits.ai")!) {
                Text("Estimated AI impact calculations")
                Text("ecologits.ai")
            }
		} label: {
			Image(systemName: "ellipsis")
				.font(.system(size: 12, weight: .medium))
				.frame(width: 23, height: 23)
				.contentShape(Circle())
		}
		.menuStyle(.borderlessButton)
		.frame(width: 23, height: 23)
		.background(Color.secondary.opacity(isHovering ? 0.28 : 0.15), in: Circle())
		.onHover { isHovering = $0 }
		.menuIndicator(.hidden)
		.foregroundStyle(.secondary)
		.accessibilityLabel("More")
		.help("More")
	}
}
