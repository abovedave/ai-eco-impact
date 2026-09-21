import SwiftUI

/// Shows the hovered point's date while hovering the chart, otherwise a
/// static headline, plus the last-refreshed timestamp trailing on the same line.
struct ChartHeaderView: View {
	let hoveredDate: Date?
	let lastUpdated: Date
	let isRefreshing: Bool
	let onRefresh: () -> Void

	private static let headline = "AI usage impact"

	var body: some View {
		HStack(alignment: .firstTextBaseline) {
			Group {
				if let hoveredDate {
					Text(hoveredDate.formatted(date: .abbreviated, time: .omitted))
				} else {
					Text(Self.headline)
                        .fontDesign(.rounded)
				}
			}
			.font(.title)
            .fontWeight(.semibold)
			.lineLimit(1)
			.layoutPriority(1)

			Spacer(minLength: 8)

			Button(action: onRefresh) {
				TimelineView(.periodic(from: .now, by: 15)) { context in
					HStack(spacing: 4) {
						Text(isRefreshing ? "Refreshing…" : lastUpdatedText(at: context.date))
							.lineLimit(1)
							.fixedSize(horizontal: true, vertical: false)
						Image(systemName: "arrow.clockwise")
					}
				}
			}
			.buttonStyle(.plain)
			.font(.caption2)
			.foregroundStyle(.secondary)
			.disabled(isRefreshing)
			.opacity(isRefreshing ? 0.5 : 1)
			.accessibilityLabel(isRefreshing ? "Refreshing…" : "Refresh")
			.help("Refresh")
		}
	}

	private static let relativeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .abbreviated
		formatter.dateTimeStyle = .named // "now" instead of "in 0 sec"
		return formatter
	}()

	private func lastUpdatedText(at now: Date) -> String {
		guard lastUpdated != .distantPast else { return "" }

		let elapsed = now.timeIntervalSince(lastUpdated)
		if elapsed < 60 {
			return "Estimated just now"
		}

		let wholeMinutesAgo = now.addingTimeInterval(-floor(elapsed / 60) * 60)
		let relative = Self.relativeFormatter.localizedString(for: wholeMinutesAgo, relativeTo: now)

		return "Estimated \(relative)"
	}
}
