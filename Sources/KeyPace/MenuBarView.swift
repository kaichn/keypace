import SwiftUI

/// Menu bar popover. The popover itself is system Liquid Glass; the action row uses
/// glass buttons grouped in one GlassEffectContainer so they read as one control cluster.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let unit = model.unit
        let today = model.today
        VStack(alignment: .leading, spacing: 14) {
            if !model.hasPermission {
                PermissionCard()
            }

            // Live readout
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if model.live != nil && !model.paused {
                        Label("Live", systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                }
                SpeedText(wpm: model.liveWPM ?? (today.sessions > 0 ? today.wpm : nil), unit: unit, size: 48)
                PaceBand(unit: unit, current: model.liveWPM ?? (today.sessions > 0 ? today.wpm : nil),
                         typical: model.typicalRange, personalBest: model.monkeytypeBest, showsLegend: false)
                    .padding(.top, 2)
            }

            // Today
            HStack(alignment: .top, spacing: 0) {
                Metric(label: "Today", value: today.sessions > 0 ? unit.format(wpm: today.wpm) : "–", detail: unit.label)
                Metric(label: "Peak", value: today.sessions > 0 ? unit.format(wpm: today.peakWPM) : "–", detail: unit.label)
                Metric(label: "Typed", value: unit.formatAmount(chars: today.netChars),
                       detail: "\(unit.amountLabel.lowercased()) · \(formatDuration(today.activeSeconds))")
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        model.paused.toggle()
                    } label: {
                        Label(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button {
                        StatsWindowController.shared.show()
                    } label: {
                        Label("Statistics", systemImage: "chart.line.uptrend.xyaxis")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("s")
                }
                .controlSize(.large)
            }

            HStack {
                SettingsLink { Text("Settings…") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                    .keyboardShortcut(",")
                Spacer()
                Button("About") { About.show() }
                Spacer()
                // Red: quitting stops tracking, unlike the other footer actions.
                Button("Quit KeyPace", role: .destructive) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var status: String {
        if !model.hasPermission { return "Not measuring" }
        if model.paused { return "Paused" }
        if let live = model.live { return "Writing in \(live.appName)" }
        return model.today.sessions > 0 ? "Today's pace" : "Waiting for you to write"
    }
}

/// Explains the permission, then hands off to the system with a single button (privacy.md).
struct PermissionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Allow keystroke counting", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("KeyPace needs Input Monitoring to count keystrokes in other apps. It never stores which keys you press.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Continue") { model.requestPermission() }
                .buttonStyle(.glassProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}
