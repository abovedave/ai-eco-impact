import Foundation

/// Which ccusage-tracked tool a slice of usage came from.
enum Tool: String, Codable, CaseIterable {
	case claudeCode = "Claude Code"
	case codex = "Codex"
	case gemini = "Gemini"
	case kimi = "Kimi"
	case grok = "Grok"

	/// "Claude Code, Codex, Gemini, Kimi, and Grok" — for the empty-state copy.
	static var supportedNamesSentence: String {
		ListFormatter.localizedString(byJoining: allCases.map(\.rawValue))
	}
}

/// One model's token usage for one day, as reported by `ccusage <tool> daily --json`.
/// Decoding is deliberately lenient: ccusage's schema has drifted before
/// (e.g. "date" became "period"), and this app should degrade gracefully
/// rather than crash when a field is missing or renamed upstream.
struct ModelUsage {
	let date: String
	let tool: Tool
	let modelName: String
	let outputTokens: Int
}

private struct CcusageDailyReport: Decodable {
	let daily: [DailyEntry]
}

private struct DailyEntry: Decodable {
	let period: String?
	let date: String?
	let modelBreakdowns: [ModelBreakdown]?

	var resolvedPeriod: String { period ?? date ?? "unknown" }
}

private struct ModelBreakdown: Decodable {
	let modelName: String?
	let outputTokens: Int?
	let reasoningOutputTokens: Int?
}

enum CcusageJSON {
	/// Parses a `ccusage <tool> daily --json` payload into a flat list of
	/// per-model, per-day usage. Any entry that can't be understood is
	/// skipped rather than failing the whole parse.
	static func parseDailyReport(_ data: Data, tool: Tool) -> [ModelUsage] {
		guard let report = try? JSONDecoder().decode(CcusageDailyReport.self, from: data) else {
			return []
		}
		var result: [ModelUsage] = []
		for day in report.daily {
			for breakdown in day.modelBreakdowns ?? [] {
				guard let modelName = breakdown.modelName else { continue }
				let outputTokens = (breakdown.outputTokens ?? 0) + (breakdown.reasoningOutputTokens ?? 0)
				result.append(ModelUsage(date: day.resolvedPeriod, tool: tool, modelName: modelName, outputTokens: outputTokens))
			}
		}
		return result
	}
}

/// Estimated energy/water/carbon for some slice of usage.
struct UsageTotals: Codable, Equatable {
	var wattHours: Double = 0
	var milliliters: Double = 0
	var carbonGrams: Double = 0

	static func + (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
		UsageTotals(
			wattHours: lhs.wattHours + rhs.wattHours,
			milliliters: lhs.milliliters + rhs.milliliters,
			carbonGrams: lhs.carbonGrams + rhs.carbonGrams
		)
	}
}

/// One plotted point: a timestamp and its estimated energy/water/carbon.
struct UsagePoint: Codable, Equatable, Identifiable {
	var id: Date { date }
	let date: Date
	var totals: UsageTotals
	var modelLabel: String = "Unknown model"
	var tool: Tool = .claudeCode
}

/// One row of the "By Model" breakdown: totals for one (model, tool) pair
/// over whatever range is currently selected.
struct ModelRow: Identifiable {
	let id: String
	let label: String
	let tool: Tool
	let totals: UsageTotals
}

/// The time ranges shown as pill buttons above the chart.
///
/// Every ccusage report here is daily-granularity, so "today" only ever has
/// one point per tool — not enough for a meaningful chart on its own.
/// `MenuContentView` handles this by showing `.week`'s points in the chart
/// while still reporting `.today`'s own totals in the header/big numbers
/// when `.today` is selected.
enum UsageRange: String, CaseIterable, Identifiable {
	case today = "Today"
	case week = "Week"
	case month = "Month"
	case all = "All"

	var id: String { rawValue }

	var displayName: String {
		switch self {
		case .today: String(localized: "Today", comment: "Range picker option")
		case .week: String(localized: "Week", comment: "Range picker option")
		case .month: String(localized: "Month", comment: "Range picker option")
		case .all: String(localized: "All", comment: "Range picker option")
		}
	}

	/// Points on/after this date belong to the range. `nil` means "all".
	func cutoffDate(now: Date = Date()) -> Date? {
		let startOfToday = Calendar.current.startOfDay(for: now)
        
		switch self {
            case .today: return startOfToday
            case .week: return Calendar.current.date(byAdding: .day, value: -6, to: startOfToday)
            case .month: return Calendar.current.date(byAdding: .day, value: -29, to: startOfToday)
            case .all: return nil
		}
	}
}

/// Everything the menu bar UI needs, computed fresh on every refresh and
/// cached to disk so relaunching the app has something to show immediately.
/// `series` is the single source of truth — per-range totals and chart data
/// are both derived from it (see `points(for:)`/`totals(for:)` below) rather
/// than precomputed, so adding a range is just adding a case to `UsageRange`.
struct UsageSnapshot: Codable, Equatable {
	var lastUpdated: Date = .distantPast
	var series: [UsagePoint] = []
	var errorMessage: String?

	func points(for range: UsageRange) -> [UsagePoint] {
		guard let cutoff = range.cutoffDate() else { return series }
		return series.filter { $0.date >= cutoff }
	}

	func totals(for range: UsageRange) -> UsageTotals {
		points(for: range).reduce(UsageTotals()) { $0 + $1.totals }
	}
}
