import Foundation

/// Persists the last computed snapshot to disk so the menu bar has real
/// numbers to show immediately on launch, before the first refresh completes.
struct UsageStore {
	private let fileURL: URL

	init() {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		let dir = base.appendingPathComponent("AIUsageMenuBar", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		fileURL = dir.appendingPathComponent("cache.json")
	}

	func load() -> UsageSnapshot? {
		guard let data = try? Data(contentsOf: fileURL) else { return nil }
		return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
	}

	func save(_ snapshot: UsageSnapshot) {
		guard let data = try? JSONEncoder().encode(snapshot) else { return }
		try? data.write(to: fileURL, options: .atomic)
	}
}
