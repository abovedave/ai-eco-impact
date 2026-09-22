# AI Usage Menu Bar

<img width="1200" height="630" alt="thumbnail" src="https://github.com/user-attachments/assets/d1b113ec-342c-4198-a143-a5c031330445" />

[![Release](https://github.com/abovedave/ai-eco-impact/actions/workflows/release.yml/badge.svg)](https://github.com/abovedave/ai-eco-impact/actions/workflows/release.yml)

macOS menu bar app. Estimates energy, water, and carbon footprint of your coding-agent CLI usage (Claude Code, Codex, Gemini CLI) using local data only.

Inspired by [this MIT Tech Review piece](https://www.technologyreview.com/2025/05/20/1116327/ai-energy-usage-climate-footprint-big-tech/).

## How it works

- **[ccusage](https://github.com/ryoppippi/ccusage)** reads each tool's local logs and reports daily token usage.
- **[EcoLogits](https://ecologits.ai)** methodology turns tokens into Wh / mL / gCO2e, based on model size, real latency stats, datacenter PUE/WUE, and grid carbon intensity.
- Coefficients are precomputed at build time (`scripts/build-coefficients.mjs` → `Resources/coefficients.json`), not calculated live.
- Only output tokens are counted (decode dominates inference energy).
- Kimi and Grok aren't supported by EcoLogits, so their usage shows in the app but contributes $0 to environmental totals.

**Caveat:** order-of-magnitude estimate, not a measurement. Unknown/new models get mapped to the closest known model in the same family.

## Install

1. Download `AIUsageMenuBar.zip` from the [latest release](https://github.com/abovedave/ai-eco-impact/releases/latest).
2. Unzip it and drag `AIUsageMenuBar.app` to `/Applications`.
3. Open it. It's signed with a Developer ID and notarized, so it should launch normally with no Gatekeeper warning.
4. It has no Dock icon or window — look for it in the menu bar. From then on it checks for updates automatically via [Sparkle](https://sparkle-project.org).

## Build & run

```bash
brew install xcodegen                 # one-time
node scripts/build-coefficients.mjs   # regenerate coefficients.json
xcodegen generate                     # regenerate .xcodeproj from project.yml
open AIUsageMenuBar.xcodeproj         # ⌘R to build & run
```

Generated Xcode 26+ project via [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source of truth so re-run `xcodegen generate` after editing.

Runs ccusage's compiled binary directly (vendored in `Vendor/ccusage/`). Node is only needed for dev scripts, not for the built app.


## Releasing

```bash
git tag vX.X.X && git push --tags   # triggers .github/workflows/release.yml
```

That workflow builds, signs, notarizes, publishes a GitHub Release, and updates the [Sparkle](https://sparkle-project.org) appcast (`docs/appcast.xml`) for auto-updates. Auto-updates only work once the repo is public (Sparkle needs public release URLs).

One-time setup for releases (Apple Developer account required) — set these GitHub secrets:

| Secret | Source |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID cert, exported as `.p12`, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | That export's password |
| `TEAM_ID` | e.g., `Z4ZXD95E9B` |
| `NOTARY_APPLE_ID` | Apple ID email for notarization |
| `NOTARY_PASSWORD` | App-specific password ([appleid.apple.com](https://appleid.apple.com)) |
| `SPARKLE_PRIVATE_KEY` | From Sparkle's `generate_keys -x` (public half already in `project.yml`) |

Local sanity check (no notarizing/zipping):

```bash
xcodegen generate
xcodebuild -project AIUsageMenuBar.xcodeproj -scheme AIUsageMenuBar -configuration Release build
```
