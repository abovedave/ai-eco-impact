#!/usr/bin/env node
// Fetches EcoLogits' open model-repository and electricity-mix data
// (github.com/mlco2/ecologits — the CodeCarbon non-profit's peer-reviewed
// LLM-inference impact methodology, JOSS DOI 10.21105/joss.07471) and
// derives, per model family, marginal Wh-, mL- (water), and gCO2e-per-
// output-token rates by running EcoLogits' own physical model at 300 and
// 1000 output tokens and taking the slope between them — the same marginal-
// rate approach used before, just against a different upstream dataset.
// Rerun this whenever the upstream dataset changes: node scripts/build-coefficients.mjs

import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const MODELS_URL = 'https://raw.githubusercontent.com/mlco2/ecologits/main/ecologits/data/models.json';
const ELECTRICITY_MIX_URL = 'https://raw.githubusercontent.com/mlco2/ecologits/main/ecologits/data/electricity_mixes.json';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_PATH = join(__dirname, '..', 'Resources', 'coefficients.json');

// EcoLogits' physical model (ecologits/impacts/llm.py): a regression fit
// against the open ML.ENERGY Leaderboard benchmark, plus fixed server/GPU
// assumptions (a p5.48xlarge-class AWS instance, NVIDIA H100 80GB GPUs,
// 3-year hardware lifetime). These are the model itself, not dataset rows,
// so they're hardcoded here rather than re-fetched.
const MODEL_QUANTIZATION_BITS = 16;
const GPU_ENERGY_ALPHA = 1.1665273170451914e-6;
const GPU_ENERGY_BETA = -0.011205921025579175;
const GPU_ENERGY_GAMMA = 4.052928146734005e-5;
const GPU_MEMORY_GB = 80;
const GPU_EMBODIED_GWP_KG = 273;
const SERVER_GPUS = 8;
const SERVER_POWER_KW = 1.2;
const SERVER_EMBODIED_GWP_KG = 5700;
const HARDWARE_LIFESPAN_SEC = 3 * 365 * 24 * 60 * 60;
const BATCH_SIZE = 64;

// Per-provider datacenter config (ecologits/tracers/utils.py PROVIDER_CONFIG_MAP)
// and the electricity-mix zone each one is estimated in. PUE/WUE are ranges
// for Anthropic (undisclosed hosting split across AWS/Google) — see
// impactsAt() for how the range is carried through.
const PROVIDER_CONFIG = {
	anthropic: { zone: 'USA', pue: { min: 1.09, max: 1.14 }, wue: { min: 0.13, max: 0.999 } },
	openai: { zone: 'USA', pue: { min: 1.20, max: 1.20 }, wue: { min: 0.569, max: 0.569 } },
	google_genai: { zone: 'USA', pue: { min: 1.09, max: 1.09 }, wue: { min: 0.999, max: 0.999 } },
};

// Maps our own family key to the exact (provider, model name) EcoLogits
// tracks in its model repository (ecologits/data/models.json). `provider`
// scopes the app's keyword-based fallback matching (see EnvironmentalEstimator).
//
// EcoLogits doesn't track every model this app previously had a family for:
// - o3 / o3-pro (OpenAI) aren't in its repository at all — usage falls back
//   to PROVIDER_DEFAULTS.openai (gpt-5) instead of a dedicated family.
// - Kimi (Moonshot) and Grok (xAI) aren't supported by EcoLogits as a
//   provider at all — usage from those tools no longer matches any family
//   or provider default, so it's silently excluded from environmental
//   totals (EnvironmentalEstimator.estimate returns zero for an unresolved
//   model, and UsageController already filters out zero-contribution points).
const FAMILIES = [
	{ key: 'claude-sonnet-4-5', provider: 'claude', ecoProvider: 'anthropic', ecoModel: 'claude-sonnet-4-5', label: 'Claude 4.5 Sonnet' },
	{ key: 'claude-opus-4-1', provider: 'claude', ecoProvider: 'anthropic', ecoModel: 'claude-opus-4-1', label: 'Claude 4.1 Opus' },
	{ key: 'claude-haiku-4-5', provider: 'claude', ecoProvider: 'anthropic', ecoModel: 'claude-haiku-4-5', label: 'Claude 4.5 Haiku' },
	{ key: 'gpt-5', provider: 'openai', ecoProvider: 'openai', ecoModel: 'gpt-5', label: 'GPT-5' },
	{ key: 'gpt-5-mini', provider: 'openai', ecoProvider: 'openai', ecoModel: 'gpt-5-mini', label: 'GPT-5 Mini' },
	{ key: 'gpt-5-nano', provider: 'openai', ecoProvider: 'openai', ecoModel: 'gpt-5-nano', label: 'GPT-5 Nano' },
	{ key: 'o4-mini', provider: 'openai', ecoProvider: 'openai', ecoModel: 'o4-mini', label: 'o4-mini' },
	{ key: 'o1', provider: 'openai', ecoProvider: 'openai', ecoModel: 'o1', label: 'o1' },
	{ key: 'gemini-2.5-pro', provider: 'google', ecoProvider: 'google_genai', ecoModel: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro' },
	{ key: 'gemini-2.5-flash', provider: 'google', ecoProvider: 'google_genai', ecoModel: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash' },
];

// Fallback coefficients used when a model reported by ccusage doesn't match
// any known family (e.g. a brand-new model release, or o3/o3-pro — see above).
const PROVIDER_DEFAULTS = {
	claude: 'claude-sonnet-4-5',
	openai: 'gpt-5',
	google: 'gemini-2.5-pro',
};

function findModel(models, aliases, provider, name) {
	const exact = models.find((m) => m.provider === provider && m.name === name);
	if (exact) return exact;
	const alias = aliases.find((a) => a.provider === provider && a.name === name);
	if (!alias) return null;
	return models.find((m) => m.provider === provider && m.name === alias.alias) ?? null;
}

// Returns the two (active, total) parameter pairs (in billions) EcoLogits
// itself evaluates for a model with an uncertain architecture — the low end
// and high end of its estimate. For a mixture-of-experts model only the
// active-parameter count is a range; for a dense model the same {min,max}
// serves as both active and total.
function paramPairs(model) {
	const p = model.architecture.parameters;
	if (model.architecture.type === 'moe') {
		return [
			{ active: p.active.min, total: p.total },
			{ active: p.active.max, total: p.total },
		];
	}
	return [
		{ active: p.min, total: p.min },
		{ active: p.max, total: p.max },
	];
}

// Reimplements ecologits' compute_llm_impacts (ecologits/impacts/llm.py) for
// one (active, total, pue, wue) combination at a given output-token count.
// Returns the whole-request totals in Wh / gCO2e (usage + embodied) / mL water
// (usage only — embodied water isn't modeled upstream either).
function computeOnce({ active, total, outputTokens, tps, ttft, pue, wue, mixGwp, mixWue }) {
	const gpuEnergyPerTokenKWh = (GPU_ENERGY_ALPHA * Math.exp(GPU_ENERGY_BETA * BATCH_SIZE) * active + GPU_ENERGY_GAMMA) / 1000;
	const gpuEnergyKWh = outputTokens * gpuEnergyPerTokenKWh;

	// All families here have real per-model tps/ttft, so the generation
	// latency is exact rather than falling back to EcoLogits' own regression.
	const generationLatencySec = outputTokens / tps + (ttft ?? 0);

	const requiredMemoryGB = 1.2 * total * MODEL_QUANTIZATION_BITS / 8;
	const gpusNeeded = 2 ** Math.ceil(Math.log2(Math.ceil(requiredMemoryGB / GPU_MEMORY_GB)));

	const serverEnergyKWh = (generationLatencySec / 3600) * SERVER_POWER_KW * (gpusNeeded / SERVER_GPUS) * (1 / BATCH_SIZE);
	const requestItEnergyKWh = serverEnergyKWh + gpusNeeded * gpuEnergyKWh;
	const requestEnergyKWh = pue * requestItEnergyKWh;

	const usageGwpKg = requestEnergyKWh * mixGwp;
	const waterL = requestItEnergyKWh * (wue + pue * mixWue);

	const serverGpuEmbodiedGwp = (gpusNeeded / SERVER_GPUS) * SERVER_EMBODIED_GWP_KG + gpusNeeded * GPU_EMBODIED_GWP_KG;
	const embodiedGwpKg = (generationLatencySec * serverGpuEmbodiedGwp) / (HARDWARE_LIFESPAN_SEC * BATCH_SIZE);

	return {
		wh: requestEnergyKWh * 1000,
		gco2e: (usageGwpKg + embodiedGwpKg) * 1000,
		mlWater: waterL * 1000,
	};
}

// EcoLogits reports a min/max range by pairing its low-parameter pass with
// low PUE/WUE and its high pass with high PUE/WUE (every quantity here is
// purely linear in those ranges, so this pairing is exact, not an
// approximation — verified against the live calculator's own displayed
// numbers for claude-haiku-4-5 to within rounding). We only need a single
// point estimate, so we average the two passes — matching what the
// calculator itself displays as its headline number.
function impactsAt(model, outputTokens, providerConfig, mix) {
	const [low, high] = paramPairs(model);
	const passLow = computeOnce({
		active: low.active, total: low.total, outputTokens,
		tps: model.deployment?.tps, ttft: model.deployment?.ttft,
		pue: providerConfig.pue.min, wue: providerConfig.wue.min,
		mixGwp: mix.gwp, mixWue: mix.wue,
	});
	const passHigh = computeOnce({
		active: high.active, total: high.total, outputTokens,
		tps: model.deployment?.tps, ttft: model.deployment?.ttft,
		pue: providerConfig.pue.max, wue: providerConfig.wue.max,
		mixGwp: mix.gwp, mixWue: mix.wue,
	});
	return {
		wh: (passLow.wh + passHigh.wh) / 2,
		gco2e: (passLow.gco2e + passHigh.gco2e) / 2,
		mlWater: (passLow.mlWater + passHigh.mlWater) / 2,
	};
}

async function fetchJson(url) {
	console.log(`Fetching ${url} ...`);
	const res = await fetch(url);
	if (!res.ok) throw new Error(`Failed to fetch ${url}: ${res.status} ${res.statusText}`);
	return res.json();
}

async function main() {
	const [modelsData, mixData] = await Promise.all([fetchJson(MODELS_URL), fetchJson(ELECTRICITY_MIX_URL)]);
	const models = modelsData.models;
	const aliases = modelsData.aliases;
	const mixes = mixData.electricity_mixes;
	console.log(`Parsed ${models.length} models, ${mixes.length} electricity mixes.`);

	const coefficients = {};

	for (const family of FAMILIES) {
		const model = findModel(models, aliases, family.ecoProvider, family.ecoModel);
		if (!model) {
			console.warn(`  ! Skipping ${family.key}: "${family.ecoModel}" not found for provider ${family.ecoProvider}`);
			continue;
		}
		if (!model.deployment?.tps) {
			console.warn(`  ! Skipping ${family.key}: no deployment (tps/ttft) data`);
			continue;
		}

		const providerConfig = PROVIDER_CONFIG[family.ecoProvider];
		const mix = mixes.find((m) => m.name === providerConfig.zone);
		if (!mix) {
			console.warn(`  ! Skipping ${family.key}: no electricity mix for zone ${providerConfig.zone}`);
			continue;
		}

		const at300 = impactsAt(model, 300, providerConfig, mix);
		const at1000 = impactsAt(model, 1000, providerConfig, mix);

		const tokenDelta = 1000 - 300;
		let whPerOutputToken = (at1000.wh - at300.wh) / tokenDelta;
		let mlPerOutputToken = (at1000.mlWater - at300.mlWater) / tokenDelta;
		let gco2ePerOutputToken = (at1000.gco2e - at300.gco2e) / tokenDelta;
		let usedFallback = false;

		// Same rationale as before: a non-positive marginal rate isn't
		// physically meaningful, so fall back to the 300-token value's
		// simple average rate instead of reporting zero.
		if (whPerOutputToken <= 0) { whPerOutputToken = at300.wh / 300; usedFallback = true; }
		if (mlPerOutputToken <= 0) { mlPerOutputToken = at300.mlWater / 300; usedFallback = true; }
		if (gco2ePerOutputToken <= 0) { gco2ePerOutputToken = at300.gco2e / 300; usedFallback = true; }

		coefficients[family.key] = {
			label: family.label,
			provider: family.provider,
			whPerOutputToken,
			mlPerOutputToken,
			gco2ePerOutputToken,
		};
		console.log(`  - ${family.key}: ${whPerOutputToken.toFixed(6)} Wh/token, ${mlPerOutputToken.toFixed(6)} mL/token, ${gco2ePerOutputToken.toFixed(6)} gCO2e/token${usedFallback ? '  (fallback: avg-rate, non-positive slope)' : ''}`);
	}

	const output = {
		generatedAt: new Date().toISOString(),
		source: 'https://github.com/mlco2/ecologits',
		providerDefaults: PROVIDER_DEFAULTS,
		families: coefficients,
	};

	await writeFile(OUT_PATH, JSON.stringify(output, null, 2) + '\n');
	console.log(`Wrote ${OUT_PATH}`);
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
