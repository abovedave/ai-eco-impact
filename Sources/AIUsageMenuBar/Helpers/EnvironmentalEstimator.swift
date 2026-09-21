import Foundation

/// Loads the build-time-generated coefficients (see scripts/build-coefficients.mjs)
/// and turns raw output-token counts into estimated Wh / mL / gCO2e.
///
/// These are order-of-magnitude estimates derived from EcoLogits
/// (https://ecologits.ai), not a measurement of this machine's or
/// Anthropic/OpenAI/Google's actual energy use. They only account for
/// output tokens (the decode phase dominates inference energy; ccusage
/// doesn't expose per-request counts, so a separate fixed per-call cost
/// can't be estimated).
final class EnvironmentalEstimator {
	private struct CoefficientsFile: Decodable {
		struct Family: Decodable {
			let label: String
			let provider: String
			let whPerOutputToken: Double
			let mlPerOutputToken: Double
			let gco2ePerOutputToken: Double
		}
		let providerDefaults: [String: String]
		let families: [String: Family]
	}

	private let families: [String: CoefficientsFile.Family]
	private let providerDefaults: [String: String]

	/// Ordered longest-prefix-first list of known family keys, used both for
	/// exact/prefix matching and as a source of "product line" keywords
	/// (sonnet/opus/haiku, gpt-5-mini/gpt-5-nano/gpt-5, o1/o3/o3-pro/o4-mini)
	/// so a newer model generation not yet in the dataset (e.g. a future
	/// "claude-sonnet-6") still maps to a sane proxy instead of falling back
	/// to zero.
	private lazy var orderedFamilyKeys: [String] = families.keys.sorted { $0.count > $1.count }

	init() {
		guard let url = Bundle.main.url(forResource: "coefficients", withExtension: "json"),
			let data = try? Data(contentsOf: url),
			let decoded = try? JSONDecoder().decode(CoefficientsFile.self, from: data)
		else {
			families = [:]
			providerDefaults = [:]
			return
		}
		families = decoded.families
		providerDefaults = decoded.providerDefaults
	}

	/// Normalizes a raw ccusage model id (e.g. "claude-sonnet-4-5-20250929",
	/// "claude-sonnet-5", "gpt-5-codex", "o4-mini-2025-04-16") and matches it
	/// to a known coefficient family.
	private func resolve(modelName: String) -> CoefficientsFile.Family? {
		let normalized = normalize(modelName)

		if let exact = families[normalized] {
			return exact
		}
		// Longest key first, so e.g. "gpt-5-mini-..." matches "gpt-5-mini"
		// rather than the shorter, less specific "gpt-5". Only the
		// normalized-name-starts-with-key direction is checked: the reverse
		// would let a short normalized name (e.g. "gpt-5") spuriously match
		// a longer, unrelated key ("gpt-5-mini") just because it's a prefix
		// of it.
		for key in orderedFamilyKeys where normalized.hasPrefix(key) {
			return families[key]
		}

		// Terms like "mini" or "pro" are now used by more than one provider
		// (gpt-5-mini vs. grok-3-mini; gemini-2.5-pro vs. others), so the
		// keyword fallback below is scoped to only this provider's own
		// families — otherwise it could resolve to a different provider's
		// model entirely just because they share a naming convention.
		let provider = inferProvider(from: normalized)
		let candidateKeys: [String]
		if let provider {
			candidateKeys = orderedFamilyKeys.filter { families[$0]?.provider == provider }
		} else {
			candidateKeys = orderedFamilyKeys
		}
		if let keyword = productLineKeyword(in: normalized), let key = candidateKeys.first(where: { $0.contains(keyword) }) {
			return families[key]
		}
		if let provider, let defaultKey = providerDefaults[provider] {
			return families[defaultKey]
		}
		return nil
	}

	private func inferProvider(from normalized: String) -> String? {
		if normalized.hasPrefix("claude") { return "claude" }
		if normalized.hasPrefix("gpt") || normalized.hasPrefix("o1") || normalized.hasPrefix("o3") || normalized.hasPrefix("o4") { return "openai" }
		if normalized.hasPrefix("gemini") { return "google" }
		return nil
	}

	func estimate(modelName: String, outputTokens: Int) -> UsageTotals {
		guard let family = resolve(modelName: modelName), outputTokens > 0 else {
			return UsageTotals()
		}
		return UsageTotals(
			wattHours: family.whPerOutputToken * Double(outputTokens),
			milliliters: family.mlPerOutputToken * Double(outputTokens),
			carbonGrams: family.gco2ePerOutputToken * Double(outputTokens)
		)
	}

	func displayLabel(modelName: String) -> String {
		resolve(modelName: modelName)?.label ?? modelName
	}

	private func normalize(_ modelName: String) -> String {
		var s = modelName.lowercased()
		// Strip trailing date suffixes like "-20250929" or "-2025-08-07".
		s = s.replacingOccurrences(of: #"-\d{4}-?\d{2}-?\d{2}$"#, with: "", options: .regularExpression)
		// "-fast" is deliberately not stripped here — unlike the others, it
		// denotes a genuinely different Grok variant with its own
		// coefficients ("grok-3-mini-fast" vs "grok-3-mini"), not a tag to
		// collapse away.
		for suffix in ["-latest", "-codex", "-preview", "-high", "-medium", "-low", "-beta"] {
			if s.hasSuffix(suffix) {
				s.removeLast(suffix.count)
			}
		}
		return s
	}

	private func productLineKeyword(in normalized: String) -> String? {
		// Safe to include generic terms like "mini"/"pro" now that the
		// caller scopes candidate keys to one provider first — they no
		// longer risk matching a different provider's family.
		for keyword in ["sonnet", "opus", "haiku", "mini", "nano", "pro", "flash", "thinking"] where normalized.contains(keyword) {
			return keyword
		}
		return nil
	}
}
