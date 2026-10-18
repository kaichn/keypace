import Foundation
import Observation
import Security

/// Monkeytype's public API is read-only for ApeKeys: results and personal bests can be
/// downloaded, but nothing can be uploaded (saving a result needs a signed-in browser session
/// and passes their anti-cheat). So KeyPace imports Monkeytype data to compare against.
struct MTResult: Codable, Identifiable, Hashable {
    let _id: String
    let wpm: Double
    let acc: Double
    let rawWpm: Double?
    let mode: String
    let mode2: String
    let timestamp: Double  // milliseconds
    let language: String?

    var id: String { _id }
    var date: Date { Date(timeIntervalSince1970: timestamp / 1000) }
    var label: String { "\(mode) \(mode2)" }
}

struct MTPersonalBest: Codable, Hashable {
    let wpm: Double
    let acc: Double?
    let raw: Double?
    let language: String?
    let timestamp: Double?
    let punctuation: Bool?
    let numbers: Bool?
}

private struct Envelope<T: Decodable>: Decodable {
    let message: String
    let data: T?
}

private struct ErrorEnvelope: Decodable { let message: String }

/// Personal best for one "time" mode (15/30/60/120 s).
struct MTTimePB: Codable, Identifiable, Hashable {
    let seconds: Int
    let best: MTPersonalBest
    var id: Int { seconds }
}

@Observable
@MainActor
final class MonkeytypeSync {
    private(set) var results: [MTResult] = []
    private(set) var personalBests: [MTTimePB] = []
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var lastError: String?
    /// Remembered in UserDefaults so launching never has to touch the Keychain.
    private(set) var hasKey = UserDefaults.standard.bool(forKey: "monkeytypeConnected") {
        didSet { UserDefaults.standard.set(hasKey, forKey: "monkeytypeConnected") }
    }
    /// The ApeKey, read from the Keychain at most once per run (only when syncing).
    private var cachedKey: String?

    private struct Cache: Codable {
        var results: [MTResult]
        var personalBests: [MTTimePB]
        var lastSync: Date?
    }

    private let cacheURL = AppPaths.dataDir.appendingPathComponent("monkeytype.json")

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            results = cache.results
            personalBests = cache.personalBests
            lastSync = cache.lastSync
        }
        // Older versions didn't store the flag; a previous sync means a key was saved.
        if UserDefaults.standard.object(forKey: "monkeytypeConnected") == nil {
            hasKey = lastSync != nil
        }
    }

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete() } else { Keychain.save(trimmed) }
        cachedKey = trimmed.isEmpty ? nil : trimmed
        hasKey = !trimmed.isEmpty
        lastError = nil
    }

    func forget() {
        Keychain.delete()
        cachedKey = nil
        hasKey = false
        results = []
        personalBests = []
        lastSync = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// ApeKeys may only fetch /results 30 times per day, so sync automatically at most every 6 h.
    func autoSyncIfDue() {
        guard hasKey else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < 6 * 3600 { return }
        Task { await sync() }
    }

    func sync() async {
        guard hasKey, !isSyncing else { return }
        if cachedKey == nil { cachedKey = Keychain.read() }
        guard let key = cachedKey else {
            lastError = "The saved ApeKey couldn't be read from the Keychain. Paste it again to reconnect."
            hasKey = false
            return
        }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            // Only ask for results newer than what we already have.
            var path = "/results?limit=1000"
            if let newest = results.map(\.timestamp).max() {
                path += "&onOrAfterTimestamp=\(Int(newest) + 1)"
            }
            let fresh: [MTResult] = try await get(path, key: key) ?? []
            var byID = Dictionary(results.map { ($0._id, $0) }, uniquingKeysWith: { a, _ in a })
            for r in fresh { byID[r._id] = r }
            results = byID.values.sorted { $0.timestamp < $1.timestamp }

            var pbs: [MTTimePB] = []
            for seconds in [15, 30, 60, 120] {
                if let best = try await personalBest(seconds: seconds, key: key) {
                    pbs.append(MTTimePB(seconds: seconds, best: best))
                }
            }
            personalBests = pbs
            lastSync = Date()
            saveCache()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func personalBest(seconds: Int, key: String) async throws -> MTPersonalBest? {
        let path = "/users/personalBests?mode=time&mode2=\(seconds)"
        let data = try await fetch(path, key: key)
        // Depending on the account this is one PB or one per language/settings combo; take the fastest.
        if let list = try? JSONDecoder().decode(Envelope<[MTPersonalBest]>.self, from: data).data {
            return list.max { $0.wpm < $1.wpm }
        }
        return try? JSONDecoder().decode(Envelope<MTPersonalBest>.self, from: data).data
    }

    private func get<T: Decodable>(_ path: String, key: String) async throws -> T? {
        let data = try await fetch(path, key: key)
        return try JSONDecoder().decode(Envelope<T>.self, from: data).data
    }

    private func fetch(_ path: String, key: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.monkeytype.com" + path)!)
        request.setValue("ApeKey \(key)", forHTTPHeaderField: "Authorization")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        request.setValue("KeyPace/\(version) (macOS; +https://github.com/kaichn/keypace)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.message ?? "HTTP \(status)"
            throw NSError(domain: "Monkeytype", code: status, userInfo: [NSLocalizedDescriptionKey: Self.explain(status, message)])
        }
        return data
    }

    private static func explain(_ status: Int, _ message: String) -> String {
        switch status {
        case 470: return "Invalid ApeKey."
        case 471: return "ApeKey is inactive — activate it in Monkeytype → Account settings → Ape keys."
        case 472: return "ApeKey is malformed."
        case 479, 429: return "Monkeytype rate limit reached (30 result syncs per day). Try again later."
        default: return "Monkeytype: \(message)"
        }
    }

    private func saveCache() {
        let cache = Cache(results: results, personalBests: personalBests, lastSync: lastSync)
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
    }
}

/// ApeKey lives in the login Keychain, not in a plain file.
enum Keychain {
    private static let service = "com.charl.keypace.monkeytype"
    private static let account = "apekey"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ value: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}
