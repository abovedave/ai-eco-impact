import SwiftUI

/// The CO2/water/energy stat tiles. Owns the "shown in menu bar" toggle
/// state for each stat — `App.swift` reads the same `@AppStorage` keys
/// independently to build the menu bar label, and the two stay in sync
/// automatically since they're backed by the same UserDefaults keys.
struct Stats: View {
	let totals: UsageTotals

	@AppStorage("showCO2InMenuBar") private var showCO2InMenuBar = true
	@AppStorage("showWaterInMenuBar") private var showWaterInMenuBar = true
	@AppStorage("showEnergyInMenuBar") private var showEnergyInMenuBar = true

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			StatCard(icon: "carbon.dioxide.cloud.fill", tint: .gray, value: UsageFormatting.carbon(grams: totals.carbonGrams), equivalent: UsageFormatting.carbonEquivalent(grams: totals.carbonGrams), isShownInMenuBar: $showCO2InMenuBar)
			StatCard(icon: "drop.fill", tint: .blue, value: UsageFormatting.water(milliliters: totals.milliliters), equivalent: UsageFormatting.waterEquivalent(milliliters: totals.milliliters), isShownInMenuBar: $showWaterInMenuBar)
			StatCard(icon: "bolt.fill", tint: .yellow, value: UsageFormatting.energy(wattHours: totals.wattHours), equivalent: UsageFormatting.energyEquivalent(wattHours: totals.wattHours), isShownInMenuBar: $showEnergyInMenuBar)
		}
	}
}

/// One stat tile (time/water/energy) in the popover's big-numbers row.
/// Hovering reveals an eye toggle in the corner (floated via `.overlay` so
/// it never shifts the card's own layout) controlling whether this stat is
/// included in the compact menu bar label — persisted via the `@AppStorage`
/// binding passed in from the caller, so both this popover and the menu bar
/// label (App.swift) read the same stored value.
private struct StatCard: View {
	let icon: String
	let tint: Color
	let value: String
	let equivalent: String?
	@Binding var isShownInMenuBar: Bool
	@State private var isHovering = false
	@State private var isHoveringEye = false

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			VStack(alignment: .leading, spacing: 5) {
				Image(systemName: icon)
					.foregroundStyle(tint)
				Text(value)
					.font(.title2)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
			}
			if let equivalent {
				Text(equivalent)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 7, trailing: 10))
		.overlay(alignment: .topTrailing) {
			if isHovering {
				let label = isShownInMenuBar ? "Showing in menu bar — click to hide" : "Hidden from menu bar — click to show"
				Button {
					isShownInMenuBar.toggle()
				} label: {
					Image(systemName: isShownInMenuBar ? "eye.fill" : "eye.slash")
						.font(.system(size: 12, weight: .medium))
						.frame(width: 23, height: 23)
						.background(Color.secondary.opacity(isHoveringEye ? 0.28 : 0.15), in: Circle())
						.contentShape(Circle())
						.onHover { isHoveringEye = $0 }
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
				.accessibilityLabel(label)
				.help(label)
				.offset(x: -4, y: 4)
			}
		}
		.overlay(
			RoundedRectangle(cornerRadius: 10)
				.stroke(Color.secondary.opacity(0.2), lineWidth: 1)
		)
		.onHover { hovering in
			isHovering = hovering
		}
		.animation(.easeInOut(duration: 0.1), value: isHovering)
	}
}
