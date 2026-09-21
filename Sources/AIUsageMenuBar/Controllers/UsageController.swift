import Foundation
import Combine

/// Ties together fetching (ccusage), estimation (EcoLogits-derived
/// coefficients), and disk caching, and exposes a single published snapshot
/// for the menu bar UI to render.
@MainActor
final class UsageController: ObservableObject {
	@Published private(set) var snapshot: UsageSnapshot
	@Published private(set) var isRefreshing = false

	private let fetcher = UsageFetcher()
	private let estimator = EnvironmentalEstimator()
	private let store = UsageStore()
	private var timer: Timer?

	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.timeZone = .current
		return formatter
	}()

	init() {
		snapshot = UsageStore().load() ?? UsageSnapshot()
		start()
	}

	private func start(refreshInterval: TimeInterval = 5 * 60) {
		Task { await refresh() }
		timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
			Task { await self?.refresh() }
		}
	}

	func refresh() async {
		isRefreshing = true
		defer { isRefreshing = false }

		let (usage, errorMessage) = await fetcher.fetchAll()
		let computed = aggregate(usage: usage, errorMessage: errorMessage)
		snapshot = computed
		store.save(computed)
	}

	private func aggregate(usage: [ModelUsage], errorMessage: String?) -> UsageSnapshot {
		var points: [UsagePoint] = []

		// One point per (day, model) — keeping models separate (rather than
		// folding same-day models together) preserves per-model attribution
		// for the "By Model" list.
		for entry in usage {
			let contribution = estimator.estimate(modelName: entry.modelName, outputTokens: entry.outputTokens)
			guard contribution != UsageTotals(), let date = Self.dayFormatter.date(from: entry.date) else { continue }
			let label = estimator.displayLabel(modelName: entry.modelName)
			points.append(UsagePoint(date: date, totals: contribution, modelLabel: label, tool: entry.tool))
		}

		points.sort { $0.date < $1.date }

		return UsageSnapshot(
			lastUpdated: Date(),
			series: points,
			errorMessage: usage.isEmpty ? errorMessage : nil
		)
	}
}
