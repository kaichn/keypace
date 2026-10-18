import AppKit
import Observation
import ServiceManagement

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    private(set) var sessions: [TypingSession] = []
    private(set) var live: LiveSession?
    private(set) var hasPermission = KeyMonitor.hasPermission
    private(set) var monitorRunning = false
    var paused: Bool = UserDefaults.standard.bool(forKey: Prefs.paused) {
        didSet {
            UserDefaults.standard.set(paused, forKey: Prefs.paused)
            if paused { finishLiveSession() }
        }
    }
    var unit: SpeedUnit = Prefs.currentUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: Prefs.unit) }
    }

    let monkeytype = MonkeytypeSync()

    @ObservationIgnored let store = Store()
    @ObservationIgnored private let monitor = KeyMonitor()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var frontApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication

    private init() {
        Prefs.register()
        unit = Prefs.currentUnit
        paused = UserDefaults.standard.bool(forKey: Prefs.paused)
        sessions = store.all()
        monitor.onKey = { [weak self] kind, t in self?.handle(kind, at: t) }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.frontApp = app
                self?.finishLiveSession()  // a session never spans two apps
            }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishLiveSession() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishLiveSession() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        startMonitoring()
        monkeytype.autoSyncIfDue()
    }

    // MARK: Permission / monitor

    func startMonitoring() {
        // Only assign on change: every assignment re-renders observing views.
        let granted = KeyMonitor.hasPermission
        if granted != hasPermission { hasPermission = granted }
        if !granted { return }
        let running = monitor.start()
        if running != monitorRunning { monitorRunning = running }
    }

    func requestPermission() {
        if !KeyMonitor.requestPermission() { KeyMonitor.openPrivacySettings() }
        startMonitoring()
    }

    private func tick() {
        // Pick up permission granted in System Settings without a relaunch.
        if !monitorRunning {
            startMonitoring()
        }
        guard let live else { return }
        let timeout = UserDefaults.standard.double(forKey: Prefs.sessionTimeout)
        if ProcessInfo.processInfo.systemUptime - live.lastUptime > timeout {
            finishLiveSession()
        }
    }

    // MARK: Session tracking

    private var excludedApps: Set<String> {
        let raw = UserDefaults.standard.string(forKey: Prefs.excludedApps) ?? ""
        return Set(raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private func handle(_ kind: KeyKind, at t: TimeInterval) {
        guard !paused else { return }
        let app = frontApp ?? NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier ?? "unknown"
        if bundleID == Bundle.main.bundleIdentifier || excludedApps.contains(bundleID) { return }

        let defaults = UserDefaults.standard
        if let live, t - live.lastUptime > defaults.double(forKey: Prefs.sessionTimeout) || live.appBundleID != bundleID {
            finishLiveSession()
        }
        if live == nil {
            // A session starts with a character, not with deleting.
            guard kind == .char else { return }
            live = LiveSession(at: t, appBundleID: bundleID, appName: app?.localizedName ?? bundleID)
        }
        live?.record(kind, at: t, pauseThreshold: defaults.double(forKey: Prefs.pauseThreshold))
    }

    func finishLiveSession() {
        guard let s = live else { return }
        live = nil
        guard var session = s.finished(minChars: UserDefaults.standard.integer(forKey: Prefs.minChars)) else { return }
        session.id = store.insert(session)
        sessions.append(session)
    }

    func delete(ids: Set<Int64>) {
        store.delete(ids: ids)
        sessions.removeAll { ids.contains($0.id) }
    }

    func deleteAll() {
        store.deleteAll()
        sessions.removeAll()
    }

    // MARK: Derived

    /// Live speed shown in the menu bar (only once there is enough data to be meaningful).
    var liveWPM: Double? {
        guard let live, live.activeSeconds >= 3, live.netChars >= 10 else { return nil }
        return live.wpm
    }

    var today: Aggregate {
        let start = Calendar.current.startOfDay(for: Date())
        return Aggregate(sessions.filter { $0.start >= start })
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("KeyPace: launch at login failed: \(error)")
            }
        }
    }

    // MARK: Export

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "keypace-sessions.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let iso = ISO8601DateFormatter()
        var csv = "start,end,app,bundle_id,chars,backspaces,active_seconds,net_wpm,bpm,peak_wpm,accuracy\n"
        for s in sessions {
            let name = s.appName.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(iso.string(from: s.start)),\(iso.string(from: s.end)),\"\(name)\",\(s.appBundleID),\(s.chars),\(s.backspaces),"
            csv += String(format: "%.1f,%.1f,%.0f,%.1f,%.3f\n", s.activeSeconds, s.wpm, s.cpm, s.peakWPM, s.accuracy)
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
