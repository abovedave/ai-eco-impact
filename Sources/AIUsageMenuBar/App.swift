import SwiftUI

@main
struct AIUsageMenuBarApp: App {
	@StateObject private var controller = UsageController()
	@StateObject private var appUpdater = AppUpdater()
	// Same keys as the corresponding controls in MenuContentView/Stats —
	// two @AppStorage instances for the same key stay in sync automatically.
	@AppStorage("showCO2InMenuBar") private var showCO2InMenuBar = true
	@AppStorage("showWaterInMenuBar") private var showWaterInMenuBar = true
	@AppStorage("showEnergyInMenuBar") private var showEnergyInMenuBar = true
	@AppStorage("selectedMenuBarRange") private var selectedRange: UsageRange = .today

	var body: some Scene {
		MenuBarExtra {
			MenuContentView(controller: controller, appUpdater: appUpdater)
		} label: {
            Image(systemName: menuBarIcon)
			Text(menuBarText)
		}
		.menuBarExtraStyle(.window)
	}

	// MenuBarExtra's label only reliably renders one Image + one Text — SF
	// Symbols embedded inside Text (via `+` or interpolation) never render,
	// and multiple sibling Image views collapse to showing only one. So a
	// single active stat gets its own icon; several stats share the generic
	// plug icon since we can't show more than one image reliably.
	private var activeStats: [(symbol: String, text: String)] {
		let totals = controller.snapshot.totals(for: selectedRange)
		guard totals.wattHours > 0 else { return [] }

		var stats: [(symbol: String, text: String)] = []
		if showCO2InMenuBar {
			stats.append((symbol: "carbon.dioxide.cloud.fill", text: UsageFormatting.carbon(grams: totals.carbonGrams)))
		}
		if showWaterInMenuBar {
			stats.append((symbol: "drop.fill", text: UsageFormatting.water(milliliters: totals.milliliters)))
		}
		if showEnergyInMenuBar {
			stats.append((symbol: "bolt.fill", text: UsageFormatting.energy(wattHours: totals.wattHours)))
		}
		return stats
	}

	private var menuBarIcon: String {
		let stats = activeStats
		return stats.count == 1 ? stats[0].symbol : "poweroutlet.type.f.fill"
	}

	private var menuBarText: String {
		let stats = activeStats
		guard !stats.isEmpty else { return "" }
		return " " + stats.map(\.text).joined(separator: " · ")
	}
}
