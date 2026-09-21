import SwiftUI

/// Shown instead of the stats/chart/breakdown when there's no usage data at
/// all yet — a fresh install, or none of the supported tools have local logs
/// to read — so the popover explains itself instead of just looking blank.
struct EmptyStateView: View {
	var body: some View {
		VStack(spacing: 8) {
			Image(systemName: "chart.xyaxis.line")
				.font(.system(size: 26))
				.foregroundStyle(.secondary)
			Text("No data found (yet)")
				.font(.headline)
			Text("Local usage logs for \(Tool.supportedNamesSentence) are read locally by [ccusage](https://ccusage.com).")
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 28)
	}
}

#Preview {
	EmptyStateView()
		.padding(14)
		.frame(width: 380)
}
