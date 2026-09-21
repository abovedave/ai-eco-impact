import Foundation

// Foundation's `UnitEnergy` has no plain watt-hours case (only kilowattHours),
// so extend the real type with one rather than invent a parallel unit
// hierarchy — this keeps it interoperable with any other `Measurement<UnitEnergy>`.
// Coefficient is relative to UnitEnergy's base unit (joules): 1 Wh = 3600 J.
extension UnitEnergy {
	static let wattHours = UnitEnergy(symbol: "Wh", converter: UnitConverterLinear(coefficient: 3600))
}

extension Measurement where UnitType: Dimension {
	/// Converts to the smallest unit in `scales` (given smallest-to-largest)
	/// whose magnitude falls under `target`, walking up the list until one
	/// does — e.g. Wh for anything under 1000, else kWh. This is the same
	/// approach as paulw11/MeasurementScaler: `.naturalScale` (Foundation's
	/// own auto-unit-selection) doesn't fit here — tested, it drifts energy
	/// into calories and volume into centiliters — so the candidate units
	/// and threshold are explicit instead.
	func scaled(through scales: [UnitType], target: Double) -> Measurement {
		guard !scales.isEmpty else { return self }
		var result = converted(to: scales[0])
		if result.value.magnitude > target {
			for unit in scales {
				result.convert(to: unit)
				if result.value.magnitude < target {
					break
				}
			}
		}
		return result
	}
}

private let measurementNumberStyle = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))

enum UsageFormatting {
	/// The unit `energy(wattHours:)` would pick for this value — exposed so
	/// callers showing several values side by side (e.g. the model breakdown
	/// list) can settle on one shared unit rather than each row scaling
	/// independently.
	static func preferredEnergyUnit(wattHours: Double) -> UnitEnergy {
		Measurement(value: wattHours, unit: UnitEnergy.wattHours)
			.scaled(through: [.wattHours, .kilowattHours], target: 1000)
			.unit
	}

	/// See `preferredEnergyUnit`.
	static func preferredWaterUnit(milliliters: Double) -> UnitVolume {
		Measurement(value: milliliters, unit: UnitVolume.milliliters)
			.scaled(through: [.milliliters, .liters], target: 1000)
			.unit
	}

	/// See `preferredEnergyUnit`.
	static func preferredCarbonUnit(grams: Double) -> UnitMass {
		Measurement(value: grams, unit: UnitMass.grams)
			.scaled(through: [.grams, .kilograms], target: 1000)
			.unit
	}

	static func energy(wattHours: Double) -> String {
		energy(wattHours: wattHours, unit: preferredEnergyUnit(wattHours: wattHours))
	}

	/// Same as `energy(wattHours:)` but in a caller-chosen unit instead of
	/// picking one from this value alone.
	static func energy(wattHours: Double, unit: UnitEnergy) -> String {
		let measurement = Measurement(value: wattHours, unit: UnitEnergy.wattHours).converted(to: unit)
		return measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: measurementNumberStyle))
	}

	static func water(milliliters: Double) -> String {
		water(milliliters: milliliters, unit: preferredWaterUnit(milliliters: milliliters))
	}

	/// Same as `water(milliliters:)` but in a caller-chosen unit instead of
	/// picking one from this value alone.
	static func water(milliliters: Double, unit: UnitVolume) -> String {
		let measurement = Measurement(value: milliliters, unit: UnitVolume.milliliters).converted(to: unit)
		// Foundation's own UnitVolume symbols render lowercase ("ml"/"l") at
		// .abbreviated width — "l" alone reads too easily as "1", so the
		// symbol is supplied explicitly here rather than via .unit.symbol.
		let symbol = unit == .liters ? "L" : "mL"
		// mL is whole-number precision (sub-mL precision isn't meaningful here);
		// liters keeps fractional digits since a rounded liter value would lose
		// too much of the number (e.g. "0 L" for 400 mL).
		let numberStyle: FloatingPointFormatStyle<Double> = unit == .liters
			? measurementNumberStyle
			: .number.precision(.fractionLength(0))
		return measurement.value.formatted(numberStyle) + " " + symbol
	}

	/// Rounds to a whole number (or `fractionLength` digits) for display, but
	/// never shows a bare "0" for a genuinely positive value — "0 water
	/// bottles" reads as if nothing happened at all, so tiny amounts show
	/// "<1" instead.
	private static func roundedCount(_ value: Double, fractionLength: ClosedRange<Int> = 0...0) -> String {
		let formatted = value.formatted(.number.precision(.fractionLength(fractionLength)))
		return formatted == "0" ? "<1" : formatted
	}

	/// Rough, commonly-cited real-world reference quantities — not precise
	/// conversions, just enough to make a number tangible. Switches to the
	/// larger reference (same >1000-of-the-smaller-unit rule as energy/water
	/// unit switching above) so this doesn't say "4200 water bottles" for a
	/// genuinely large total.
	static func waterEquivalent(milliliters: Double) -> String {
		let literBottle = 0.5
		let olympicPool = 2_500_000.0
		let liters = milliliters / 1000
		let bottles = liters / literBottle
		if bottles > 1000 {
			let pools = liters / olympicPool
			return "\(roundedCount(pools)) Olympic swimming pools"
		}
		return "\(roundedCount(bottles)) water bottles"
	}

	static func energyEquivalent(wattHours: Double) -> String {
		// Phone charges rather than kettle boils — kettles are a daily-use
		// appliance in the UK/Ireland/Australia/NZ but not really elsewhere,
		// where a phone charge is a genuinely universal reference point.
		let phoneCharge = 12.0 // ~full charge, typical smartphone battery
		let householdDay = 29_000.0 // rough household daily electricity use
		let charges = wattHours / phoneCharge
		if charges > 1000 {
			let days = wattHours / householdDay
			return "\(roundedCount(days)) days of household power"
		}
		return "\(roundedCount(charges)) phone charges"
	}

	static func carbon(grams: Double) -> String {
		carbon(grams: grams, unit: preferredCarbonUnit(grams: grams))
	}

	/// Same as `carbon(grams:)` but in a caller-chosen unit instead of
	/// picking one from this value alone.
	static func carbon(grams: Double, unit: UnitMass) -> String {
		let measurement = Measurement(value: grams, unit: UnitMass.grams).converted(to: unit)
		return measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: measurementNumberStyle))
	}

	static func carbonEquivalent(grams: Double) -> String {
		// The dataset's own large-scale reference points (its "Gasoline Car
		// Equiv" / "Atlantic Flight Equiv" columns) validate these as sensible
		// units for carbon specifically, same rough-reference spirit as the
		// water/energy equivalents above.
		let carMile = 404.0 // ~g CO2e per mile, average gasoline passenger car (US EPA)
		let atlanticFlight = 700_000.0 // ~g CO2e, one-way economy passenger, NY-London
		let miles = grams / carMile
		if miles > 1000 {
			let flights = grams / atlanticFlight
			return "\(roundedCount(flights, fractionLength: 0...1)) NYC-LON flights"
		}
		// US and UK measure road distances in miles; everywhere else uses km —
		// the same locale rule Foundation's own `usage: .road` measurement
		// formatting applies (the UK is metric for most things, but not roads).
		let usesMiles = Locale.current.measurementSystem == .us || Locale.current.measurementSystem == .uk
		if usesMiles {
			return "\(roundedCount(miles)) miles driven"
		}
		let kilometers = miles * 1.60934
		return "\(roundedCount(kilometers)) km driven"
	}
}
