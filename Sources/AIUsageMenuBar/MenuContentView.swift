import SwiftUI

struct MenuContentView: View {
	@ObservedObject var controller: UsageController
	@ObservedObject var appUpdater: AppUpdater
	// Persisted (not @State) so the menu bar label (App.swift, reading the
	// same key) shows whichever period the user last picked here, the same
	// way the eye toggles control which stats it shows.
	@AppStorage("selectedMenuBarRange") private var selectedRange: UsageRange = .today
	@State private var hoveredPoint: UsagePoint?

	// "Today" doesn't have enough points on its own for a meaningful chart
	// (see UsageRange), so the chart falls back to the week's points while
	// the header/big numbers below still report .today's own totals.
	private var chartRange: UsageRange { selectedRange == .today ? .week : selectedRange }
	private var rangeTotals: UsageTotals { controller.snapshot.totals(for: selectedRange) }
	/// What the stat block shows: the hovered point's own totals while
	/// hovering, otherwise the selected range's totals.
	private var displayedTotals: UsageTotals { hoveredPoint?.totals ?? rangeTotals }

	/// Grouped by (model, tool) over the selected range — not `chartRange`,
	/// so "Today" shows today's actual model mix rather than the week's.
	private var modelBreakdown: [ModelRow] {
		var byKey: [String: ModelRow] = [:]
		for point in controller.snapshot.points(for: selectedRange) {
			let key = "\(point.modelLabel)|\(point.tool.rawValue)"
			let existing = byKey[key]?.totals ?? UsageTotals()
			byKey[key] = ModelRow(id: key, label: point.modelLabel, tool: point.tool, totals: existing + point.totals)
		}
		return byKey.values.sorted { $0.totals.wattHours > $1.totals.wattHours }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			if let error = controller.snapshot.errorMessage {
				Label(error, systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.orange)
			}

			// Today/Week/Month/All picker
			HStack {
				Picker("", selection: $selectedRange) {
					ForEach(UsageRange.allCases) { range in
						Text(range.displayName).tag(range)
					}
				}
                .pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
				Spacer()
				SettingsMenu(appUpdater: appUpdater, onQuit: { NSApplication.shared.terminate(nil) })
			}

			ChartHeaderView(
				hoveredDate: hoveredPoint?.date,
				lastUpdated: controller.snapshot.lastUpdated,
				isRefreshing: controller.isRefreshing,
				onRefresh: { Task { await controller.refresh() } }
			)

			if controller.snapshot.series.isEmpty && controller.snapshot.errorMessage == nil {
				EmptyStateView()
			} else {
				Stats(totals: displayedTotals)

				UsageChart(rawPoints: controller.snapshot.points(for: chartRange), hoveredPoint: $hoveredPoint)
					.frame(height: 150)

				ModelBreakdownList(rows: modelBreakdown)
			}
		}
		.padding(14)
		.frame(width: 380)
	}
}
