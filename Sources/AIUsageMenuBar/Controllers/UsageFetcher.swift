import Foundation

enum UsageFetchError: LocalizedError {
	case binaryNotFound
	case processFailed(String)

	var errorDescription: String? {
		switch self {
		case .binaryNotFound:
			return "Bundled ccusage binary missing — reinstall the app."
		case .processFailed(let detail):
			return "ccusage failed: \(detail)"
		}
	}
}

/// Runs the native `ccusage` binary vendored under Vendor/ccusage (see
/// README.md) to read locally-logged Claude Code / Codex CLI usage.
///
/// This is a real, standalone compiled executable — the same one the
/// `ccusage` npm package installs as an optional per-platform dependency
/// (`@ccusage/ccusage-darwin-arm64` / `-darwin-x64`) — not something we
/// compiled ourselves. Running it directly means the app has zero
/// dependency on Node.js/npx being installed at all.
struct UsageFetcher {
	/// Every tool ccusage supports here, each via its own scoped `daily`
	/// report. Adding a provider is just adding a line — `CcusageJSON.parseDailyReport`
	/// already handles any of them generically.
	private static let tools: [(tool: Tool, args: [String])] = [
		(.claudeCode, ["claude", "daily", "--json"]),
		(.codex, ["codex", "daily", "--json"]),
		(.gemini, ["gemini", "daily", "--json"]),
		(.kimi, ["kimi", "daily", "--json"]),
		(.grok, ["grok", "daily", "--json"]),
	]

	func fetchAll() async -> ([ModelUsage], String?) {
		guard let binaryPath = Self.bundledBinaryPath() else {
			return ([], UsageFetchError.binaryNotFound.localizedDescription)
		}

		// Most of these tools just aren't installed/used — only surface an
		// error if EVERY source failed, so a single-tool user never sees a
		// spurious warning about the other four.
		let results = await withTaskGroup(of: (usage: [ModelUsage], error: String?).self) { group in
			for entry in Self.tools {
				group.addTask {
					let (data, error) = await self.run(binaryPath: binaryPath, args: entry.args)
					guard let data else { return ([], error) }
					return (CcusageJSON.parseDailyReport(data, tool: entry.tool), nil)
				}
			}
			var all: [(usage: [ModelUsage], error: String?)] = []
			for await result in group { all.append(result) }
			return all
		}

		let usage = results.flatMap(\.usage)
		let combinedError = results.allSatisfy { $0.error != nil } ? results.first?.error : nil
		return (usage, combinedError)
	}

	private func run(binaryPath: String, args: [String]) async -> (Data?, String?) {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.executableURL = URL(fileURLWithPath: binaryPath)
			process.arguments = args

			let outPipe = Pipe()
			let errPipe = Pipe()
			process.standardOutput = outPipe
			process.standardError = errPipe

			do {
				try process.run()
			} catch {
				continuation.resume(returning: (nil, "Failed to launch ccusage: \(error.localizedDescription)"))
				return
			}

			let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
			process.waitUntilExit()

			if process.terminationStatus != 0 {
				let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
				let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
				continuation.resume(returning: (nil, message?.isEmpty == false ? message : "exit code \(process.terminationStatus)"))
				return
			}

			continuation.resume(returning: (outData, nil))
		}
	}

	private static func bundledBinaryPath() -> String? {
		#if arch(arm64)
		let arch = "darwin-arm64"
		#else
		let arch = "darwin-x64"
		#endif
		guard let path = Bundle.main.resourceURL?
			.appendingPathComponent("ccusage/\(arch)/ccusage")
			.path,
			FileManager.default.isExecutableFile(atPath: path)
		else {
			return nil
		}
		return path
	}
}
