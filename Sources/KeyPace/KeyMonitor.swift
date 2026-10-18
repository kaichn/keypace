import AppKit
import CoreGraphics

enum KeyKind {
    case char
    case backspace
}

/// Listens to global key-down events through a listen-only CGEventTap.
/// Requires the "Input Monitoring" privacy permission. It only classifies each key
/// (character vs. backspace) — the typed character itself is discarded immediately.
@MainActor
final class KeyMonitor {
    /// Key kind, monotonic time, and the process that receives the key. The receiver can
    /// differ from the frontmost app: Spotlight and other launcher panels take keys without
    /// becoming active.
    var onKey: ((KeyKind, TimeInterval, pid_t) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt (first time only) and adds the app to the Input Monitoring list.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,  // annotated: the receiving process is known
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables slow taps; switch it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown, let kind = Self.classify(event) else { return }
        let target = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        onKey?(kind, ProcessInfo.processInfo.systemUptime, target)
    }

    nonisolated static func classify(_ event: CGEvent) -> KeyKind? {
        let flags = event.flags
        // Shortcuts (⌘C, ⌃A, …) are not typing.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { return nil }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if keyCode == 51 { return .backspace }  // held backspace still deletes characters
        if isRepeat { return nil }              // held letter keys are not typing speed

        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        let c = buffer[0]
        if c == 13 || c == 3 { return .char }          // Return / Enter
        if c < 32 || c == 127 { return nil }           // Tab, Esc, other control keys
        if (0xF700...0xF8FF).contains(c) { return nil } // arrows, F-keys, Home/End, fwd delete
        return .char
    }
}
