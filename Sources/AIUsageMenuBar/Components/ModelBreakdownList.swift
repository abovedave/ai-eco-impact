import Foundation
import SwiftUI

private let co2Icon = "cloud.fill"
private let waterIcon = "drop.fill"
private let energyIcon = "bolt.fill"

/// The "By Model" list below the chart — models grouped by tool (keyed off
/// `Tool.rawValue`), each group collapsible so the list stays short when
/// several tools are in play. Renders nothing when empty, so callers don't
/// need to conditionally include it.
struct ModelBreakdownList: View {
	let rows: [ModelRow]

	// A plain Button + `if` toggle rather than `DisclosureGroup`: on macOS
	// DisclosureGroup's expand/collapse is animated by the native control
	// itself, not by a SwiftUI transaction, so `.transaction { $0.animation
	// = nil }` can't suppress it. This version never calls `withAnimation`,
	// so nothing animates.
	@State private var expandedTools: Set<Tool> = []

	/// Rows bucketed by tool, each bucket sorted by watt-hours (heaviest
	/// model first) and carrying its own combined totals so the header stays
	/// informative while collapsed. Buckets are ordered by their combined
	/// watt-hours, so the tool contributing the most stays on top.
	private var groupedByTool: [(tool: Tool, rows: [ModelRow], totals: UsageTotals)] {
		Dictionary(grouping: rows, by: \.tool)
			.map { tool, rows in
				let sorted = rows.sorted { $0.totals.wattHours > $1.totals.wattHours }
				return (tool: tool, rows: sorted, totals: sorted.reduce(UsageTotals()) { $0 + $1.totals })
			}
			.sorted { $0.totals.wattHours > $1.totals.wattHours }
	}

	/// One unit per metric, shared by every row in the list (rather than each
	/// row picking its own via magnitude) so values stay short and directly
	/// comparable — chosen from the list's combined total, same as the big
	/// numbers above the chart.
	private var overallTotals: UsageTotals {
		rows.reduce(UsageTotals()) { $0 + $1.totals }
	}
	private var carbonUnit: UnitMass { UsageFormatting.preferredCarbonUnit(grams: overallTotals.carbonGrams) }
	private var waterUnit: UnitVolume { UsageFormatting.preferredWaterUnit(milliliters: overallTotals.milliliters) }
	private var energyUnit: UnitEnergy { UsageFormatting.preferredEnergyUnit(wattHours: overallTotals.wattHours) }

	var body: some View {
		Group {
			if !rows.isEmpty {
				VStack(alignment: .leading, spacing: 10) {
					ForEach(groupedByTool, id: \.tool) { group in
						// One Grid per tool — the header (button) row and the
						// per-model rows below share it, so the co2/water/
						// energy columns line up exactly between them.
						// A single-model group has nothing to reveal — its one row's
						// totals are identical to the header's — so it renders as a
						// plain, non-expandable line instead of a dropdown that would
						// just restate the header.
						let isExpandable = group.rows.count > 1
						Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
							Button {
								if isExpandable { toggle(group.tool) }
							} label: {
								GridRow {
									HStack(spacing: 8) {
										if isExpandable {
											Image(systemName: "chevron.right")
												.font(.caption2)
												.foregroundStyle(.secondary)
												.rotationEffect(.degrees(expandedTools.contains(group.tool) ? 90 : 0))
												.frame(width: 8)
										}
										Text(group.tool.rawValue)
									}
									.frame(maxWidth: .infinity, alignment: .leading)
									.gridColumnAlignment(.leading)

									MetricValue(icon: co2Icon, text: UsageFormatting.carbon(grams: group.totals.carbonGrams, unit: carbonUnit))
										.gridColumnAlignment(.trailing)
									MetricValue(icon: waterIcon, text: UsageFormatting.water(milliliters: group.totals.milliliters, unit: waterUnit))
										.gridColumnAlignment(.trailing)
									MetricValue(icon: energyIcon, text: UsageFormatting.energy(wattHours: group.totals.wattHours, unit: energyUnit))
										.gridColumnAlignment(.trailing)
								}
								// Rectangle, not the default shape-from-visible-content, so the
								// row's full bounds are tappable — not just the text/icon glyphs.
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)

							if isExpandable && expandedTools.contains(group.tool) {
								ModelRowsTable(rows: group.rows, carbonUnit: carbonUnit, waterUnit: waterUnit, energyUnit: energyUnit)
							}
						}
						.font(.callout)
					}
				}
			}
		}
	}

	private func toggle(_ tool: Tool) {
		if expandedTools.contains(tool) {
			expandedTools.remove(tool)
		} else {
			expandedTools.insert(tool)
		}
	}
}

/// A tool's per-model rows. `GridRow` composes through plain view structs,
/// so embedding this inside the parent `Grid` (rather than wrapping its own)
/// keeps these columns aligned with the tool header row above them.
private struct ModelRowsTable: View {
	let rows: [ModelRow]
	let carbonUnit: UnitMass
	let waterUnit: UnitVolume
	let energyUnit: UnitEnergy

	var body: some View {
		ForEach(rows, id: \.id) { row in
			GridRow {
				Text(row.label)
					.padding(.leading, 16)
					.frame(maxWidth: .infinity, alignment: .leading)
				// No icons here — the tool header row above already shows
				// them once per metric, so repeating them on every model
				// would just be noise.
				Text(UsageFormatting.carbon(grams: row.totals.carbonGrams, unit: carbonUnit))
					.monospacedDigit()
				Text(UsageFormatting.water(milliliters: row.totals.milliliters, unit: waterUnit))
					.monospacedDigit()
				Text(UsageFormatting.energy(wattHours: row.totals.wattHours, unit: energyUnit))
					.monospacedDigit()
			}
			.foregroundStyle(.secondary)
		}
	}
}

/// One metric (CO2/water/energy) as an icon + value — shared by the tool
/// header row and each model's own row so the two line up.
private struct MetricValue: View {
	let icon: String
	let text: String

	var body: some View {
		HStack(spacing: 4) {
			Image(systemName: icon)
				.imageScale(.small)
                .foregroundStyle(.secondary)
			Text(text)
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
	}
}
