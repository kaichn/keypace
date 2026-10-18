import SwiftUI

// Design tokens
// - Accent (system, follows the user's accent color) = you, passive pace.
// - Orange = Monkeytype tests. Never used for anything else.
// - Numerals use SF Pro Rounded with monospaced digits, like a speedometer readout.
// - Content sits on plain cards; Liquid Glass is left to the system's functional layer
//   (sidebar, toolbar, menu bar popover, buttons).
enum Theme {
    static let monkeytype = Color.orange
    static let cardRadius: CGFloat = 18

    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// Content-layer container: opaque, adapts to light/dark, hairline edge for Increase Contrast.
struct Card<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).font(.headline) }
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        }
    }
}

/// A speed value with its unit, e.g. "322 BPM".
struct SpeedText: View {
    let wpm: Double?
    let unit: SpeedUnit
    var size: CGFloat = 22

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(wpm.map { unit.format(wpm: $0) } ?? "–")
                .font(Theme.number(size))
                .contentTransition(.numericText())
            Text(unit.label)
                .font(.system(size: max(11, size * 0.38), weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

/// One labelled figure inside a metrics row.
struct Metric: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(Theme.number(20))
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Signature element: where a pace sits relative to your normal range and your test speed.
/// Track = 0 … scale max. Soft band = typical range (middle half of your sessions).
/// Dot = current pace. Orange tick = Monkeytype personal best.
struct PaceBand: View {
    let unit: SpeedUnit
    let current: Double?
    let typical: ClosedRange<Double>?
    let personalBest: Double?
    var showsLegend = true
    var currentLabel = "Now"

    private var scaleMax: Double {
        max(personalBest ?? 0, current ?? 0, typical?.upperBound ?? 0, 20) * 1.12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = { (v: Double) in w * CGFloat(min(max(v / scaleMax, 0), 1)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 8)
                    if let t = typical {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: max(10, x(t.upperBound) - x(t.lowerBound)), height: 8)
                            .offset(x: x(t.lowerBound))
                    }
                    if let pb = personalBest {
                        Capsule()
                            .fill(Theme.monkeytype)
                            .frame(width: 3, height: 18)
                            .offset(x: x(pb) - 1.5)
                    }
                    if let c = current {
                        Circle()
                            .fill(Color.accentColor)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2.5))
                            .frame(width: 16, height: 16)
                            .offset(x: x(c) - 8)
                            .animation(.smooth, value: c)
                    }
                }
                .frame(height: geo.size.height)
            }
            .frame(height: 18)

            if showsLegend {
                HStack(spacing: 14) {
                    if let current {
                        legend(Circle().fill(Color.accentColor).frame(width: 8, height: 8),
                               "\(currentLabel) \(unit.format(wpm: current))")
                    }
                    if let t = typical {
                        legend(Capsule().fill(Color.accentColor.opacity(0.35)).frame(width: 14, height: 6),
                               "Typical \(unit.format(wpm: t.lowerBound))–\(unit.format(wpm: t.upperBound))")
                    }
                    if let pb = personalBest {
                        legend(Capsule().fill(Theme.monkeytype).frame(width: 3, height: 10),
                               "Monkeytype PB \(unit.format(wpm: pb))")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace compared with your typical range")
        .accessibilityValue(accessibilityText)
    }

    private func legend(_ swatch: some View, _ text: String) -> some View {
        HStack(spacing: 5) { swatch; Text(text).monospacedDigit() }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let current { parts.append("\(currentLabel.lowercased()) \(unit.format(wpm: current)) \(unit.label)") }
        if let t = typical { parts.append("typical \(unit.format(wpm: t.lowerBound)) to \(unit.format(wpm: t.upperBound))") }
        if let pb = personalBest { parts.append("Monkeytype best \(unit.format(wpm: pb))") }
        return parts.joined(separator: ", ")
    }
}

extension Array where Element == Double {
    /// Linear-interpolated percentile, p in 0…1.
    func percentile(_ p: Double) -> Double? {
        guard !isEmpty else { return nil }
        let s = sorted()
        let pos = p * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
}

extension AppModel {
    /// Middle half (25th–75th percentile) of session speeds over the last 30 days.
    var typicalRange: ClosedRange<Double>? {
        let from = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let speeds = sessions.filter { $0.start >= from && $0.activeSeconds >= 20 }.map(\.wpm)
        guard speeds.count >= 3, let lo = speeds.percentile(0.25), let hi = speeds.percentile(0.75) else { return nil }
        return lo...hi
    }

    /// Monkeytype 60 s personal best (or the best available duration).
    var monkeytypeBest: Double? {
        let pbs = monkeytype.personalBests
        return (pbs.first { $0.seconds == 60 } ?? pbs.max { $0.best.wpm < $1.best.wpm })?.best.wpm
    }
}
