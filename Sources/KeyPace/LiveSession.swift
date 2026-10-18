import Foundation

/// Typing currently in progress (not yet saved). Holds all of KeyPace's speed maths,
/// kept free of AppKit and UserDefaults so it can be unit-tested.
///
/// Definitions (same as Monkeytype where they overlap):
/// - 1 word = 5 characters.
/// - Net characters = characters typed − backspaces (each backspace undoes one character).
/// - Active time = sum of gaps between keystrokes, leaving out any gap longer than the
///   pause threshold (thinking time).
/// - Speed = net characters / 5 per active minute (WPM).
/// - Peak burst = most net characters within any 10 s of active time, as WPM.
struct LiveSession {
    var start: Date
    var startUptime: TimeInterval
    var lastUptime: TimeInterval
    var appBundleID: String
    var appName: String
    var chars = 0
    var backspaces = 0
    var activeSeconds: Double = 0
    var peakWPM: Double = 0
    /// Recent keystrokes for the peak-burst window: (active-time stamp, +1 char / −1 backspace).
    var burstWindow: [(at: TimeInterval, delta: Int)] = []

    static let burstSeconds: Double = 10
    /// Sessions shorter than this many active seconds are not saved.
    static let minimumActiveSeconds: Double = 5

    init(start: Date = Date(), at t: TimeInterval, appBundleID: String, appName: String) {
        self.start = start
        self.startUptime = t
        self.lastUptime = t
        self.appBundleID = appBundleID
        self.appName = appName
    }

    var netChars: Int { max(0, chars - backspaces) }
    var wpm: Double { activeSeconds > 0 ? Double(netChars) / 5 / activeSeconds * 60 : 0 }

    /// Adds one keystroke at monotonic time `t` (seconds).
    mutating func record(_ kind: KeyKind, at t: TimeInterval, pauseThreshold: Double) {
        let gap = t - lastUptime
        if gap > 0 && gap <= pauseThreshold { activeSeconds += gap }
        lastUptime = max(lastUptime, t)

        switch kind {
        case .backspace: backspaces += 1
        case .char: chars += 1
        }

        burstWindow.append((activeSeconds, kind == .char ? 1 : -1))
        burstWindow.removeAll { activeSeconds - $0.at > Self.burstSeconds }
        if activeSeconds >= Self.burstSeconds {
            let net = max(0, burstWindow.reduce(0) { $0 + $1.delta })
            peakWPM = max(peakWPM, Double(net) / 5 * (60 / Self.burstSeconds))
        }
    }

    /// The session to save, or nil when it is too short to be meaningful.
    func finished(minChars: Int) -> TypingSession? {
        guard netChars >= minChars, activeSeconds >= Self.minimumActiveSeconds else { return nil }
        return TypingSession(
            start: start,
            end: start.addingTimeInterval(lastUptime - startUptime),
            appBundleID: appBundleID, appName: appName,
            chars: chars, backspaces: backspaces,
            activeSeconds: activeSeconds,
            // The best 10 s is never slower than the session as a whole (and short sessions
            // never fill a 10 s window), so the session's own speed is the floor.
            peakWPM: max(peakWPM, wpm)
        )
    }
}
