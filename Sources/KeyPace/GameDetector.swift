import AppKit
import notify
import os

/// Which apps count as games. It uses the same rules as macOS Game Mode:
/// - Apps that declare a games category in their Info.plist.
/// - Apple's Game Mode database (allow and block lists for Steam, Epic, Minecraft, Roblox, …),
///   which macOS keeps up to date in `/System/Library/AssetsV2`.
///
/// Game Mode's on/off state itself is only available to privileged system tools, so KeyPace
/// applies the rules directly. That also covers games played in a window, where Game Mode
/// stays off.
struct GameRules: Equatable {
    var allowBundleIDs: Set<String> = []
    var allowProcessNames: Set<String> = []
    var allowPartialPaths: [String] = []
    var blockBundleIDs: Set<String> = []
    var blockProcessNames: Set<String> = []

    /// Where macOS keeps the Game Mode database.
    static let assetDir = URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_GamePolicy_DB1")

    /// Rules KeyPace adds on top of Apple's.
    static let extras = GameRules(
        allowPartialPaths: [
            "steamapps/common",          // Steam, in case the database is missing
            "/minecraft/runtime/java",   // official Minecraft launcher
            "PrismLauncher/java/",       // Minecraft through Prism Launcher
        ],
        blockBundleIDs: [
            "com.valvesoftware.steam", "com.valvesoftware.steam.helper",
            "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.brave.Browser",
        ],
        blockProcessNames: ["Steam Helper"]
    )

    /// Apple's database merged with KeyPace's extras.
    static func load() -> GameRules {
        var rules = extras
        let fm = FileManager.default
        let assets = (try? fm.contentsOfDirectory(at: assetDir, includingPropertiesForKeys: nil)) ?? []
        for asset in assets where asset.pathExtension == "asset" {
            guard let files = fm.enumerator(at: asset.appendingPathComponent("AssetData"), includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.path.contains("/Personalities/") && file.pathExtension == "plist" {
                if let data = try? Data(contentsOf: file) { rules.merge(personality: data) }
            }
        }
        return rules
    }

    /// Adds one Game Mode "personality" plist (`Model.Policy.Allow` / `Block`).
    mutating func merge(personality data: Data) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let model = plist["Model"] as? [String: Any],
              let policy = model["Policy"] as? [String: Any] else { return }
        let allow = policy["Allow"] as? [String: Any] ?? [:]
        let block = policy["Block"] as? [String: Any] ?? [:]
        allowBundleIDs.formUnion(allow["BundleIdentifiers"] as? [String] ?? [])
        allowProcessNames.formUnion(allow["ProcessNames"] as? [String] ?? [])
        allowPartialPaths += (allow["ProcessPartialPaths"] as? [String] ?? []).filter { !allowPartialPaths.contains($0) }
        blockBundleIDs.formUnion(block["BundleIdentifiers"] as? [String] ?? [])
        blockProcessNames.formUnion(block["ProcessNames"] as? [String] ?? [])
    }

    /// Game Mode lists process names the way the kernel stores them: cut to 15 characters.
    private static func kernelName(_ name: String) -> String { String(name.prefix(15)) }

    private func matches(_ names: Set<String>, _ processName: String?) -> Bool {
        guard let processName else { return false }
        let short = Self.kernelName(processName)
        return names.contains { Self.kernelName($0) == short }
    }

    /// - Parameter category: the app's `LSApplicationCategoryType`.
    func isGame(bundleID: String?, processName: String?, executablePath: String?, category: String?, supportsGameMode: Bool = false) -> Bool {
        if let bundleID, blockBundleIDs.contains(bundleID) { return false }
        if matches(blockProcessNames, processName) { return false }

        if let bundleID, allowBundleIDs.contains(bundleID) { return true }
        if matches(allowProcessNames, processName) { return true }
        if let executablePath, allowPartialPaths.contains(where: { executablePath.contains($0) }) { return true }
        if supportsGameMode { return true }
        return Self.isGameCategory(category)
    }

    /// `public.app-category.games` and its subcategories (`…action-games`, `…puzzle-games`, …).
    static func isGameCategory(_ category: String?) -> Bool {
        guard let c = category?.lowercased(), c.hasPrefix("public.app-category.") else { return false }
        return c == "public.app-category.games" || c.hasSuffix("-games")
    }
}

/// Checks running apps against `GameRules` and caches the answer per process.
@MainActor
final class GameDetector {
    private var rules = GameRules.load()
    private var cache: [pid_t: Bool] = [:]
    private var updateToken = NOTIFY_TOKEN_INVALID
    private let log = Logger(subsystem: "com.charl.keypace", category: "games")

    init() {
        log.info("game rules: \(self.rules.allowPartialPaths.count) paths, \(self.rules.allowBundleIDs.count) apps allowed, \(self.rules.blockBundleIDs.count) blocked")
        // macOS posts this when it installs a new Game Mode database.
        notify_register_dispatch("com.apple.gamepolicy.mobileasset.DB.update", &updateToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        rules = GameRules.load()
        cache.removeAll()
        log.info("game rules reloaded")
    }

    func isGame(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        if let known = cache[pid] { return known }
        let info = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }
        let result = rules.isGame(
            bundleID: app.bundleIdentifier,
            processName: app.executableURL?.lastPathComponent,
            executablePath: app.executableURL?.path,
            category: info?["LSApplicationCategoryType"] as? String,
            supportsGameMode: info?["GCSupportsGameMode"] as? Bool ?? false
        )
        if cache.count > 500 { cache.removeAll() }
        cache[pid] = result
        if result { log.info("game detected: \(app.bundleIdentifier ?? app.executableURL?.path ?? "pid \(pid)", privacy: .public)") }
        return result
    }

    func forget(_ pid: pid_t) { cache[pid] = nil }
}
