import SwiftUI
import Charts

/// The water/energy line+area chart, with hover-to-inspect support.
///
/// Owns its own day-aggregation: Claude's underlying data is per-5-hour
/// block, so a single calendar day can show up as several separate raw
/// points — plotting every block makes multi-day ranges look needlessly
/// jagged and puts multiple x-axis points on what's visually "today". This
/// view takes the raw points and buckets them by day itself, so callers
/// don't need to know that's a chart-specific rendering detail.
struct UsageChart: View {
	let rawPoints: [UsagePoint]
	@Binding var hoveredPoint: UsagePoint?

	private var points: [UsagePoint] { Self.aggregatedByDay(rawPoints) }

	var body: some View {
		Chart {
			ForEach(points) { point in
				LineMark(x: .value("Time", point.date), y: .value("Amount", point.totals.milliliters), series: .value("Metric", "Water"))
					.foregroundStyle(by: .value("Metric", "Water"))
				AreaMark(x: .value("Time", point.date), y: .value("Amount", point.totals.milliliters), series: .value("Metric", "Water"), stacking: .unstacked)
					.foregroundStyle(by: .value("Metric", "Water"))
					.opacity(0.12)
			}
			ForEach(points) { point in
				LineMark(x: .value("Time", point.date), y: .value("Amount", point.totals.wattHours), series: .value("Metric", "Energy"))
					.foregroundStyle(by: .value("Metric", "Energy"))
				AreaMark(x: .value("Time", point.date), y: .value("Amount", point.totals.wattHours), series: .value("Metric", "Energy"), stacking: .unstacked)
					.foregroundStyle(by: .value("Metric", "Energy"))
					.opacity(0.12)
			}
			ForEach(points) { point in
				LineMark(x: .value("Time", point.date), y: .value("Amount", point.totals.carbonGrams), series: .value("Metric", "Carbon"))
					.foregroundStyle(by: .value("Metric", "Carbon"))
				AreaMark(x: .value("Time", point.date), y: .value("Amount", point.totals.carbonGrams), series: .value("Metric", "Carbon"), stacking: .unstacked)
					.foregroundStyle(by: .value("Metric", "Carbon"))
					.opacity(0.12)
			}
			if let hoveredPoint {
				RuleMark(x: .value("Time", hoveredPoint.date))
					.foregroundStyle(.secondary.opacity(0.4))
				PointMark(x: .value("Time", hoveredPoint.date), y: .value("Amount", hoveredPoint.totals.milliliters))
					.foregroundStyle(Color.blue)
				PointMark(x: .value("Time", hoveredPoint.date), y: .value("Amount", hoveredPoint.totals.wattHours))
					.foregroundStyle(Color.yellow)
				PointMark(x: .value("Time", hoveredPoint.date), y: .value("Amount", hoveredPoint.totals.carbonGrams))
					.foregroundStyle(Color.gray)
			}
		}
		.chartForegroundStyleScale(["Water": Color.blue, "Energy": Color.yellow, "Carbon": Color.gray])
		.chartLegend(.hidden)
		.chartYAxis(.hidden) // Water (mL) and energy (Wh) share one axis but aren't the same unit —
		// bare numbers on it would be ambiguous, so only the shape/trend is shown here; exact
		// values are in the stat block above, which updates live as you hover.
		.chartXAxis {
			AxisMarks(values: .automatic(desiredCount: 4)) { _ in
				AxisGridLine()
				AxisValueLabel(format: xAxisFormat)
			}
		}
		.chartOverlay { proxy in
			GeometryReader { geometry in
				Rectangle().fill(.clear)
					.contentShape(Rectangle())
					.onContinuousHover { phase in
						switch phase {
						case .active(let location):
							let plotFrame = geometry[proxy.plotAreaFrame]
							let relativeX = location.x - plotFrame.origin.x
							guard let date: Date = proxy.value(atX: relativeX) else { return }
							hoveredPoint = nearestPoint(to: date)
						case .ended:
							hoveredPoint = nil
						}
					}
			}
		}
	}

	/// Based on the actual span of the visible points rather than the
	/// selected range name — "All" might be five weeks of history today but
	/// years of it later, and month+year granularity on a five-week span
	/// makes most ticks show the same label (e.g. repeated "Aug 26"). No
	/// hour-level format here: points are day-aggregated, so a span under a
	/// day or two just means few active days in the range, not fine-grained
	/// intraday data worth showing hours for.
	private var xAxisFormat: Date.FormatStyle {
		guard let first = points.first?.date, let last = points.last?.date else {
			return .dateTime.month(.abbreviated).day()
		}
		let span = last.timeIntervalSince(first)
		if span < 60 * 60 * 24 * 180 { // under ~6 months: day-level detail is still meaningful
			return .dateTime.month(.abbreviated).day()
		}
		return .dateTime.month(.abbreviated).year(.twoDigits)
	}

	private func nearestPoint(to date: Date) -> UsagePoint? {
		points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
	}

	private static func aggregatedByDay(_ points: [UsagePoint]) -> [UsagePoint] {
		var byDay: [Date: UsagePoint] = [:]
		for point in points {
			let day = Calendar.current.startOfDay(for: point.date)
			if var existing = byDay[day] {
				existing.totals = existing.totals + point.totals
				byDay[day] = existing
			} else {
				byDay[day] = UsagePoint(date: day, totals: point.totals, modelLabel: point.modelLabel, tool: point.tool)
			}
		}
		return byDay.values.sorted { $0.date < $1.date }
	}
}
