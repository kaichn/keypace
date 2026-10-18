import Charts
import SwiftUI

struct MonkeytypePane: View {
    @Environment(AppModel.self) private var model
    let sessions: [TypingSession]
    let range: TimeRange
    @State private var keyInput = ""

    var body: some View {
        let mt = model.monkeytype
        let unit = model.unit
        let passive = Aggregate(sessions)
        let results = mt.results.filter { r in range.start.map { r.date >= $0 } ?? true }

        PaneScroll {
            if !mt.personalBests.isEmpty {
                Card(title: "Tests vs. Real Writing",
                     subtitle: "Your everyday pace (\(range == .all ? "all time" : "last " + range.rawValue)) next to your Monkeytype personal bests") {
                    PaceBand(unit: unit, current: passive.sessions > 0 ? passive.wpm : nil,
                             typical: model.typicalRange, personalBest: model.monkeytypeBest,
                             currentLabel: "Average")
                    Divider()
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(mt.personalBests) { pb in
                            Metric(label: "Best \(pb.seconds) s",
                                   value: "\(unit.format(wpm: pb.best.wpm)) \(unit.label)",
                                   detail: passive.wpm > 0 ? String(format: "You write at %.0f %%", passive.wpm / pb.best.wpm * 100) : nil)
                        }
                    }
                }
            }

            if !results.isEmpty {
                Card(title: "Test Results over Time",
                     subtitle: "Orange: Monkeytype tests. Line: your daily passive pace.") {
                    Chart {
                        ForEach(dailyPoints(sessions)) { p in
                            LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit.label, unit.value(fromWPM: p.agg.wpm)))
                                .foregroundStyle(by: .value("Source", "Passive"))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                        ForEach(results) { r in
                            PointMark(x: .value("Day", r.date), y: .value(unit.label, unit.value(fromWPM: r.wpm)))
                                .foregroundStyle(by: .value("Source", "Monkeytype"))
                                .symbol(.diamond)
                                .symbolSize(30)
                                .accessibilityLabel("Monkeytype \(r.label), \(r.date.formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityValue("\(unit.format(wpm: r.wpm)) \(unit.label)")
                        }
                    }
                    .chartForegroundStyleScale(["Passive": Color.accentColor, "Monkeytype": Theme.monkeytype])
                    .chartYAxisLabel(unit.label)
                    .frame(height: 240)
                }

                let mtAvg = results.map(\.wpm).reduce(0, +) / Double(results.count)
                Card(title: "Recent Tests", subtitle: "\(results.count) tests · average \(unit.format(wpm: mtAvg)) \(unit.label)") {
                    Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 6) {
                        GridRow {
                            Text("Date").gridColumnAlignment(.leading)
                            Text("Mode"); Text(unit.label); Text("Accuracy")
                        }
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Divider()
                        ForEach(results.suffix(12).reversed()) { r in
                            GridRow {
                                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                                Text(r.label)
                                Text(unit.format(wpm: r.wpm)).fontWeight(.semibold)
                                Text(String(format: "%.1f %%", r.acc))
                            }
                            .monospacedDigit()
                        }
                    }
                }
            }

            Card(title: "Monkeytype Account",
                 subtitle: "KeyPace reads your test results to compare. Monkeytype doesn't accept uploads from other apps, so passive sessions stay on this Mac.") {
                if mt.hasKey {
                    HStack(spacing: 12) {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let last = mt.lastSync {
                            Text("Updated \(last.formatted(.relative(presentation: .named)))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect", role: .destructive) { mt.forget() }
                        Button {
                            Task { await mt.sync() }
                        } label: {
                            if mt.isSyncing { ProgressView().controlSize(.small) } else { Text("Sync Now") }
                        }
                        .disabled(mt.isSyncing)
                    }
                } else {
                    Text("In Monkeytype, open Account Settings → Ape Keys, create and activate a key, then paste it here.")
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("ApeKey", text: $keyInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                        Button("Connect", action: save)
                            .buttonStyle(.borderedProminent)
                            .disabled(keyInput.isEmpty)
                    }
                    Link("Open Monkeytype Ape Keys", destination: URL(string: "https://monkeytype.com/account-settings?tab=apeKeys")!)
                        .font(.subheadline)
                }
                if let err = mt.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func save() {
        model.monkeytype.setKey(keyInput)
        keyInput = ""
        Task { await model.monkeytype.sync() }
    }
}
