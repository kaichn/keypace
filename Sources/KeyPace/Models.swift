import Foundation

/// One continuous stretch of typing in one app. Only counts are stored — never the text.
struct TypingSession: Identifiable, Hashable, Sendable {
    var id: Int64 = 0
    var start: Date
    var end: Date
    var appBundleID: String
    var appName: String
    /// Printable keystrokes (letters, digits, punctuation, space, return).
    var chars: Int
    var backspaces: Int
    /// Seconds spent actually typing (pauses longer than the pause threshold are left out).
    var activeSeconds: Double
    /// Best 10 seconds of typing time, in net WPM (backspaces subtracted, like the average).
    var peakWPM: Double

    /// Characters that survived: every backspace removes one typed character.
    var netChars: Int { max(0, chars - backspaces) }
    /// Net characters per active minute (shown as "BPM" when that unit is chosen).
    var cpm: Double { activeSeconds > 0 ? Double(netChars) / activeSeconds * 60 : 0 }
    /// Net words per minute, standard 5 characters = 1 word (same definition as Monkeytype).
    var wpm: Double { cpm / 5 }
    /// Estimated accuracy: share of keystrokes that did not have to be deleted.
    var accuracy: Double { chars > 0 ? Double(netChars) / Double(chars) : 1 }
}

/// Weighted totals across many sessions (weighted by time, not by session count).
struct Aggregate {
    var sessions = 0
    var chars = 0
    var backspaces = 0
    var activeSeconds: Double = 0
    var peakWPM: Double = 0

    init() {}
    init<S: Sequence>(_ items: S) where S.Element == TypingSession {
        for s in items { add(s) }
    }

    mutating func add(_ s: TypingSession) {
        sessions += 1
        chars += s.chars
        backspaces += s.backspaces
        activeSeconds += s.activeSeconds
        peakWPM = max(peakWPM, s.peakWPM)
    }

    var netChars: Int { max(0, chars - backspaces) }
    var wpm: Double { activeSeconds > 0 ? Double(netChars) / 5 / activeSeconds * 60 : 0 }
    var accuracy: Double { chars > 0 ? Double(netChars) / Double(chars) : 1 }
}

enum SpeedUnit: String, CaseIterable, Identifiable {
    case bpm, wpm
    var id: String { rawValue }
    var label: String { self == .bpm ? "BPM" : "WPM" }
    var longLabel: String {
        self == .bpm ? "BPM — characters (Anschläge) per minute" : "WPM — words per minute (5 chars = 1 word)"
    }
    /// Converts a WPM value into this unit.
    func value(fromWPM wpm: Double) -> Double { self == .bpm ? wpm * 5 : wpm }
    func format(wpm: Double) -> String { String(format: "%.0f", value(fromWPM: wpm)) }

    /// Amount typed, in this unit's terms: words (5 characters each) or characters.
    var amountLabel: String { self == .bpm ? "Characters" : "Words" }
    func formatAmount(chars: Int) -> String {
        (self == .bpm ? chars : Int((Double(chars) / 5).rounded())).formatted()
    }
}

enum Prefs {
    static let unit = "unit"
    static let pauseThreshold = "pauseThreshold"
    static let sessionTimeout = "sessionTimeout"
    static let minChars = "minChars"
    static let excludedApps = "excludedApps"
    static let showLiveInMenuBar = "showLiveInMenuBar"
    static let paused = "paused"

    static func register() {
        UserDefaults.standard.register(defaults: [
            unit: SpeedUnit.wpm.rawValue,
            pauseThreshold: 2.0,
            sessionTimeout: 20.0,
            minChars: 30,
            showLiveInMenuBar: true,
            paused: false,
            excludedApps: [
                "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                "com.apple.keychainaccess", "com.apple.Passwords", "org.keepassxc.keepassxc",
            ].joined(separator: "\n"),
        ])
    }

    static var currentUnit: SpeedUnit {
        SpeedUnit(rawValue: UserDefaults.standard.string(forKey: unit) ?? "") ?? .wpm
    }
}

enum AppPaths {
    /// ~/Library/Application Support/KeyPace (override with KEYPACE_DATA_DIR for testing).
    static let dataDir: URL = {
        let url = ProcessInfo.processInfo.environment["KEYPACE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KeyPace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
