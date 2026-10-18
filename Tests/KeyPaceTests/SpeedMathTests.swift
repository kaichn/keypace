import CoreGraphics
import Foundation
import Testing
@testable import KeyPace

/// Types `count` characters, one every `interval` seconds, starting at `from`.
private func type(_ s: inout LiveSession, _ count: Int, every interval: Double, from: Double, pause: Double = 2) -> Double {
    var t = from
    for _ in 0..<count { s.record(.char, at: t, pauseThreshold: pause); t += interval }
    return t - interval
}

private func newSession(at t: Double = 0) -> LiveSession {
    LiveSession(start: Date(timeIntervalSince1970: 0), at: t, appBundleID: "test", appName: "Test")
}

@Suite("Speed definitions")
struct SpeedDefinitionTests {
    @Test("Steady typing: 5 chars/s is 60 WPM")
    func steadyTyping() {
        var s = newSession()
        _ = type(&s, 301, every: 0.2, from: 0)          // 300 gaps of 0.2 s = 60 s
        #expect(abs(s.activeSeconds - 60) < 0.001)
        #expect(abs(s.wpm - 60.2) < 0.01)                // 301 chars / 5 per minute
    }

    @Test("Each backspace removes one character from the net count")
    func backspacesAreSubtracted() {
        var s = newSession()
        var t = type(&s, 100, every: 0.2, from: 0)
        for _ in 0..<10 { t += 0.2; s.record(.backspace, at: t, pauseThreshold: 2) }
        #expect(s.chars == 100)
        #expect(s.backspaces == 10)
        #expect(s.netChars == 90)
    }

    @Test("Pauses longer than the threshold are not typing time")
    func pausesAreExcluded() {
        var s = newSession()
        let end = type(&s, 51, every: 0.2, from: 0)         // 10 s of typing
        _ = type(&s, 51, every: 0.2, from: end + 30)        // 30 s thinking, then 10 s more
        #expect(abs(s.activeSeconds - 20) < 0.001)
    }

    @Test("A pause exactly at the threshold still counts")
    func thresholdIsInclusive() {
        var s = newSession()
        s.record(.char, at: 0, pauseThreshold: 2)
        s.record(.char, at: 2, pauseThreshold: 2)
        #expect(s.activeSeconds == 2)
    }
}

@Suite("Peak burst")
struct PeakBurstTests {
    @Test("Steady typing: peak equals the average")
    func steadyPeak() {
        var s = newSession()
        _ = type(&s, 301, every: 0.2, from: 0)
        #expect(abs(s.peakWPM - 60) <= 1.2)                  // 50–51 chars in any 10 s window
    }

    @Test("Regression: pauses can't drag the peak below the average")
    func pausesDontDilutePeak() {
        // The 6 BPM bug: a 10 s wall-clock window covered mostly thinking time.
        var s = newSession()
        var t = type(&s, 20, every: 0.15, from: 0)
        t = type(&s, 20, every: 0.15, from: t + 5)
        _ = type(&s, 20, every: 0.15, from: t + 5)
        let saved = s.finished(minChars: 1)!
        #expect(saved.peakWPM >= saved.wpm)
    }

    @Test("Regression: the peak counts net characters, like the average")
    func peakIsNet() {
        var s = newSession()
        var t = 0.0
        for i in 0..<200 {                                   // every 5th key is a backspace
            s.record(i % 5 == 4 ? .backspace : .char, at: t, pauseThreshold: 2)
            t += 0.1
        }
        // 10 keys/s, of which 8 chars and 2 backspaces → 6 net chars/s = 72 net WPM.
        #expect(abs(s.peakWPM - 72) <= 2.5)
        #expect(s.peakWPM < 96)                              // gross would be 8 chars/s = 96 WPM
    }

    @Test("A burst faster than the average shows up as the peak")
    func burstIsDetected() {
        var s = newSession()
        let t = type(&s, 51, every: 0.4, from: 0)            // 30 WPM for 20 s
        _ = type(&s, 101, every: 0.1, from: t + 0.4)         // 120 WPM for 10 s
        #expect(s.peakWPM > 100)
        #expect(s.wpm < s.peakWPM)
    }
}

@Suite("Saving sessions")
struct SavingTests {
    @Test("Too few characters: not saved")
    func tooShortByChars() {
        var s = newSession()
        _ = type(&s, 20, every: 0.5, from: 0)
        #expect(s.finished(minChars: 30) == nil)
    }

    @Test("Under 5 s of typing: not saved")
    func tooShortByTime() {
        var s = newSession()
        _ = type(&s, 40, every: 0.1, from: 0)               // 3.9 s
        #expect(s.finished(minChars: 30) == nil)
    }

    @Test("Saved session keeps counts and uses wall-clock end time")
    func savedSession() {
        var s = newSession()
        let end = type(&s, 51, every: 0.2, from: 0)
        _ = type(&s, 51, every: 0.2, from: end + 30)
        let saved = s.finished(minChars: 30)!
        #expect(saved.chars == 102)
        #expect(abs(saved.end.timeIntervalSince(saved.start) - 50) < 0.001)   // includes the pause
        #expect(abs(saved.activeSeconds - 20) < 0.001)                         // excludes it
    }
}

@Suite("Short bursts")
struct ShortBurstTests {
    /// One Spotlight-style search: 12 characters at 5/s (11 gaps of 0.2 s = 2.2 s).
    private func search(at t: Double) -> LiveSession {
        var s = newSession(at: t)
        _ = type(&s, 12, every: 0.2, from: t)
        return s
    }

    @Test("One short search is too short to save on its own")
    func singleSearchIsNotSaved() {
        #expect(search(at: 0).finished(minChars: 30) == nil)
    }

    @Test("Pooled searches save once they add up, without counting the gaps between them")
    func pooledSearchesAreSaved() {
        var pool = search(at: 0)
        pool.absorb(search(at: 100))      // 100 s later: the gap must not count as typing
        #expect(pool.finished(minChars: 30) == nil)    // 24 chars, 4.4 s: still too short
        pool.absorb(search(at: 300))
        let saved = try! #require(pool.finished(minChars: 30))
        #expect(saved.chars == 36)
        #expect(abs(saved.activeSeconds - 6.6) < 0.001)
        #expect(abs(saved.wpm - 36.0 / 5 / 6.6 * 60) < 0.001)    // same speed as each search
        #expect(saved.end == saved.start.addingTimeInterval(302.2)) // spans first to last
    }
}

@Suite("Aggregates and units")
struct AggregateTests {
    private func session(chars: Int, seconds: Double) -> TypingSession {
        TypingSession(start: Date(), end: Date(), appBundleID: "a", appName: "A",
                      chars: chars, backspaces: 0, activeSeconds: seconds, peakWPM: 0)
    }

    @Test("Averages are weighted by typing time, not by session count")
    func timeWeighted() {
        // 10 min at 60 WPM + 1 min at 120 WPM → (3000 + 600) chars / 5 / 11 min ≈ 65.5
        let agg = Aggregate([session(chars: 3000, seconds: 600), session(chars: 600, seconds: 60)])
        #expect(abs(agg.wpm - 65.45) < 0.01)
    }

    @Test("WPM and BPM convert with 5 characters per word")
    func unitConversion() {
        #expect(SpeedUnit.bpm.value(fromWPM: 58) == 290)
        #expect(SpeedUnit.wpm.value(fromWPM: 58) == 58)
        #expect(SpeedUnit.wpm.formatAmount(chars: 1000) == 200.formatted())
        #expect(SpeedUnit.bpm.formatAmount(chars: 1000) == 1000.formatted())
    }

    @Test("Percentiles interpolate")
    func percentiles() {
        #expect([10.0, 20, 30, 40].percentile(0.5) == 25)
        #expect([Double]().percentile(0.5) == nil)
    }
}

@Suite("Key classification")
struct KeyClassificationTests {
    private func key(_ code: CGKeyCode, _ text: String, flags: CGEventFlags = [], repeat isRepeat: Bool = false) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        let utf16 = Array(text.utf16)
        e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        e.flags = flags
        e.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        return e
    }

    @Test func lettersSpacesAndReturnCount() {
        #expect(KeyMonitor.classify(key(0, "a")) == .char)
        #expect(KeyMonitor.classify(key(49, " ")) == .char)
        #expect(KeyMonitor.classify(key(36, "\r")) == .char)
        #expect(KeyMonitor.classify(key(37, "@", flags: .maskAlternate)) == .char)   // ⌥L on German layouts
    }

    @Test func backspaceCountsEvenWhenHeld() {
        #expect(KeyMonitor.classify(key(51, "\u{7F}")) == .backspace)
        #expect(KeyMonitor.classify(key(51, "\u{7F}", repeat: true)) == .backspace)
    }

    @Test func shortcutsAndNavigationAreIgnored() {
        #expect(KeyMonitor.classify(key(8, "c", flags: .maskCommand)) == nil)
        #expect(KeyMonitor.classify(key(0, "a", flags: .maskControl)) == nil)
        #expect(KeyMonitor.classify(key(123, "\u{F702}")) == nil)   // left arrow
        #expect(KeyMonitor.classify(key(48, "\t")) == nil)          // tab
        #expect(KeyMonitor.classify(key(53, "\u{1B}")) == nil)      // escape
    }

    @Test func heldLetterKeysAreIgnored() {
        #expect(KeyMonitor.classify(key(0, "a", repeat: true)) == nil)
    }
}
