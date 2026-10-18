import Charts
import SwiftUI

enum StatsPane: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case trends = "Trends"
    case apps = "Apps"
    case sessions = "Sessions"
    case monkeytype = "Monkeytype"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .trends: "chart.line.uptrend.xyaxis"
        case .apps: "square.grid.2x2"
        case .sessions: "list.bullet"
        case .monkeytype: "flag.checkered"
        }
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", quarter = "90 days", year = "1 year", all = "All"
    var id: String { rawValue }
    var short: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        case .year: "1Y"
        case .all: "All"
        }
    }
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }
    var start: Date? {
        days.map { Calendar.current.date(byAdding: .day, value: -($0 - 1), to: Calendar.current.startOfDay(for: Date()))! }
    }
    /// The equally long period right before this one, for comparisons.
    var previous: Range<Date>? {
        guard let days, let start else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: start)!..<start
    }
}

struct DayPoint: Identifiable {
    let day: Date
    let agg: Aggregate
    var id: Date { day }
}

func dailyPoints(_ sessions: [TypingSession]) -> [DayPoint] {
    let cal = Calendar.current
    return Dictionary(grouping: sessions) { cal.startOfDay(for: $0.start) }
        .map { DayPoint(day: $0.key, agg: Aggregate($0.value)) }
        .sorted { $0.day < $1.day }
}

struct StatsView: View {
    @Environment(AppModel.self) private var model
    // Plain view state so switching panes redraws immediately; saved to UserDefaults
    // on change (an @AppStorage round-trip made the old pane linger for a moment).
    @State private var pane: StatsPane =
        StatsPane(rawValue: UserDefaults.standard.string(forKey: "statsPane") ?? "") ?? .overview
    @State private var range: TimeRange =
        TimeRange(rawValue: UserDefaults.standard.string(forKey: "statsRange") ?? "") ?? .month

    private var filtered: [TypingSession] {
        guard let start = range.start else { return model.sessions }
        return model.sessions.filter { $0.start >= start }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { Optional(pane) }, set: { if let p = $0 { pane = p } })) {
                Section("Your Typing") {
                    ForEach([StatsPane.overview, .trends, .apps, .sessions]) { p in
                        Label(p.rawValue, systemImage: p.icon).tag(p)
                    }
                }
                Section("Compare") {
                    Label(StatsPane.monkeytype.rawValue, systemImage: StatsPane.monkeytype.icon).tag(StatsPane.monkeytype)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .onChange(of: pane) { _, p in UserDefaults.standard.set(p.rawValue, forKey: "statsPane") }
            .onChange(of: range) { _, r in UserDefaults.standard.set(r.rawValue, forKey: "statsRange") }
        } detail: {
            detail
                .navigationTitle(pane.rawValue)
                .navigationSubtitle(range == .all ? "All time" : "Last \(range.rawValue)")
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Time Range", selection: $range) {
                            ForEach(TimeRange.allCases) { r in
                                Text(r.short).tag(r).accessibilityLabel(r.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("Time range")
                    }
                }
        }
    }

    @ViewBuilder private var detail: some View {
        if model.sessions.isEmpty && pane != .monkeytype {
            EmptyStateView()
        } else {
            switch pane {
            case .overview: OverviewPane(sessions: filtered, range: range)
            case .trends: TrendsPane(sessions: filtered)
            case .apps: AppsPane(sessions: filtered)
            case .sessions: SessionsPane(sessions: filtered)
            case .monkeytype: MonkeytypePane(sessions: filtered, range: range)
            }
        }
    }
}

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ContentUnavailableView {
            Label(model.hasPermission ? "Start Writing Anywhere" : "Allow Keystroke Counting",
                  systemImage: model.hasPermission ? "keyboard" : "hand.raised")
        } description: {
            Text(model.hasPermission
                 ? "Write in any app — Mail, Notes, Slack, your editor. Each stretch of a few sentences appears here as a session."
                 : "KeyPace needs Input Monitoring to count keystrokes in other apps. It only counts them — it never stores what you type.")
        } actions: {
            if !model.hasPermission {
                Button("Continue") { model.requestPermission() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
    }
}

/// Scrolling content column shared by the dashboard panes.
struct PaneScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

// MARK: - Overview

struct OverviewPane: View {
    @Environment(AppModel.self) private var model
    let sessions: [TypingSession]
    let range: TimeRange

    var body: some View {
        let unit = model.unit
        let agg = Aggregate(sessions)
        let today = model.today
        let previous = range.previous.map { r in Aggregate(model.sessions.filter { r.contains($0.start) }) }
        let hours = Dictionary(grouping: sessions) { Calendar.current.component(.hour, from: $0.start) }
            .map { (hour: $0.key, agg: Aggregate($0.value)) }
            .sorted { $0.hour < $1.hour }
        let topApps = Dictionary(grouping: sessions, by: \.appBundleID)
            .map { (name: $0.value.last?.appName ?? $0.key, agg: Aggregate($0.value)) }
            .sorted { $0.agg.activeSeconds > $1.agg.activeSeconds }
            .prefix(5)

        PaneScroll {
            // Hero: today against your normal range — the one thing to read first.
            Card {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today").font(.headline).foregroundStyle(.secondary)
                        SpeedText(wpm: today.sessions > 0 ? today.wpm : nil, unit: unit, size: 56)
                    }
                    Spacer()
                    if let previous, previous.sessions > 0, agg.sessions > 0 {
                        TrendBadge(change: agg.wpm / previous.wpm - 1, period: range.rawValue)
                    }
                }
                PaceBand(unit: unit, current: today.sessions > 0 ? today.wpm : nil,
                         typical: model.typicalRange, personalBest: model.monkeytypeBest,
                         currentLabel: "Today")
            }

            Card {
                HStack(alignment: .top, spacing: 0) {
                    Metric(label: "Average", value: "\(unit.format(wpm: agg.wpm)) \(unit.label)",
                           detail: "Pauses excluded")
                    Divider().padding(.horizontal, 14)
                    Metric(label: "Peak Burst", value: "\(unit.format(wpm: agg.peakWPM)) \(unit.label)", detail: "Best 10 seconds")
                    Divider().padding(.horizontal, 14)
                    Metric(label: "Accuracy", value: String(format: "%.1f %%", agg.accuracy * 100), detail: "Estimated")
                    Divider().padding(.horizontal, 14)
                    Metric(label: "Typed", value: "\(unit.formatAmount(chars: agg.netChars)) \(unit.amountLabel.lowercased())",
                           detail: "\(formatDuration(agg.activeSeconds)) active")
                }
            }

            Card(title: "Pace per Day", subtitle: "Time-weighted average of each day's sessions") {
                DailyPaceChart(days: dailyPoints(sessions), unit: unit)
                    .frame(height: 220)
            }

            HStack(alignment: .top, spacing: 16) {
                Card(title: "By Hour", subtitle: "When you write fastest") {
                    Chart(hours, id: \.hour) { h in
                        BarMark(x: .value("Hour", h.hour), y: .value(unit.label, unit.value(fromWPM: h.agg.wpm)), width: .ratio(0.7))
                            .foregroundStyle(Color.accentColor.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .accessibilityLabel("\(h.hour):00")
                            .accessibilityValue("\(unit.format(wpm: h.agg.wpm)) \(unit.label)")
                    }
                    .chartXScale(domain: -0.5...23.5)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18]) { v in
                            AxisGridLine()
                            AxisValueLabel { Text("\(v.as(Int.self) ?? 0):00") }
                        }
                    }
                    .frame(height: 160)
                }
                Card(title: "Top Apps", subtitle: "Where you write most") {
                    VStack(spacing: 10) {
                        ForEach(Array(topApps), id: \.name) { a in
                            HStack {
                                Text(a.name).lineLimit(1)
                                Spacer()
                                Text(formatDuration(a.agg.activeSeconds)).foregroundStyle(.secondary).monospacedDigit()
                                Text(unit.format(wpm: a.agg.wpm)).font(Theme.number(15)).frame(minWidth: 44, alignment: .trailing)
                            }
                        }
                    }
                    .frame(minHeight: 160, alignment: .top)
                }
            }
        }
    }
}

struct TrendBadge: View {
    let change: Double
    let period: String

    var body: some View {
        let up = change >= 0
        VStack(alignment: .trailing, spacing: 2) {
            Label(String(format: "%@%.0f %%", up ? "+" : "−", abs(change) * 100),
                  systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(Theme.number(17))
                .foregroundStyle(up ? Color.green : Color.secondary)
            Text("vs. previous \(period)").font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DailyPaceChart: View {
    let days: [DayPoint]
    let unit: SpeedUnit

    var body: some View {
        let avg = rollingAverage(days, window: 7)
        Chart {
            ForEach(days) { p in
                PointMark(x: .value("Day", p.day, unit: .day), y: .value(unit.label, unit.value(fromWPM: p.agg.wpm)))
                    .foregroundStyle(Color.accentColor.opacity(0.45))
                    .symbolSize(22)
                    .accessibilityLabel(p.day.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(unit.format(wpm: p.agg.wpm)) \(unit.label)")
            }
            ForEach(avg, id: \.day) { p in
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit.label, unit.value(fromWPM: p.wpm)))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(unit.label)
    }

    private func rollingAverage(_ days: [DayPoint], window: Int) -> [(day: Date, wpm: Double)] {
        days.map { p in
            let from = Calendar.current.date(byAdding: .day, value: -(window - 1), to: p.day)!
            let inWindow = days.filter { $0.day >= from && $0.day <= p.day }
            let net = inWindow.reduce(0) { $0 + $1.agg.netChars }
            let secs = inWindow.reduce(0.0) { $0 + $1.agg.activeSeconds }
            return (p.day, secs > 0 ? Double(net) / 5 / secs * 60 : 0)
        }
    }
}

// MARK: - Trends

struct TrendsPane: View {
    @Environment(AppModel.self) private var model
    let sessions: [TypingSession]

    var body: some View {
        let unit = model.unit
        let days = dailyPoints(sessions)

        PaneScroll {
            Card(title: "Pace over Time", subtitle: "Dots are daily averages, the line is the 7-day average") {
                DailyPaceChart(days: days, unit: unit).frame(height: 240)
            }
            Card(title: "Every Session", subtitle: "Larger dots are longer sessions") {
                Chart(sessions) { s in
                    PointMark(x: .value("Time", s.start), y: .value(unit.label, unit.value(fromWPM: s.wpm)))
                        .symbolSize(min(180, 12 + s.activeSeconds / 3))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .accessibilityLabel("\(s.appName), \(s.start.formatted(date: .abbreviated, time: .shortened))")
                        .accessibilityValue("\(unit.format(wpm: s.wpm)) \(unit.label)")
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(unit.label)
                .frame(height: 220)
            }
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Volume", subtitle: "Active minutes per day") {
                    Chart(days) { p in
                        BarMark(x: .value("Day", p.day, unit: .day), y: .value("Minutes", p.agg.activeSeconds / 60))
                            .foregroundStyle(Color.accentColor.gradient)
                            .accessibilityValue("\(Int(p.agg.activeSeconds / 60)) minutes")
                    }
                    .chartYAxisLabel("min")
                    .frame(height: 160)
                }
                Card(title: "Accuracy", subtitle: "Share of keystrokes not deleted again") {
                    Chart(days) { p in
                        LineMark(x: .value("Day", p.day, unit: .day), y: .value("Accuracy", p.agg.accuracy * 100))
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.monotone)
                            .accessibilityValue(String(format: "%.1f percent", p.agg.accuracy * 100))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel("%")
                    .frame(height: 160)
                }
            }
        }
    }
}

// MARK: - Apps

struct AppStat: Identifiable {
    let bundleID: String
    let name: String
    let agg: Aggregate
    var id: String { bundleID }
}

struct AppsPane: View {
    @Environment(AppModel.self) private var model
    let sessions: [TypingSession]

    var body: some View {
        let unit = model.unit
        let apps = Dictionary(grouping: sessions, by: \.appBundleID)
            .map { AppStat(bundleID: $0.key, name: $0.value.last?.appName ?? $0.key, agg: Aggregate($0.value)) }
            .sorted { $0.agg.activeSeconds > $1.agg.activeSeconds }
        let shown = Array(apps.prefix(10))

        PaneScroll {
            Card(title: "Pace by App", subtitle: "Apps you write in most, top to bottom") {
                let maxWPM = max(shown.map(\.agg.wpm).max() ?? 1, 1)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    ForEach(shown) { a in
                        GridRow {
                            Text(a.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 140, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: max(8, geo.size.width * a.agg.wpm / maxWPM))
                                }
                            }
                            .frame(height: 10)
                            Text(unit.format(wpm: a.agg.wpm))
                                .font(Theme.number(15))
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(a.name)
                        .accessibilityValue("\(unit.format(wpm: a.agg.wpm)) \(unit.label)")
                    }
                }
            }

            Card(title: "Details") {
                Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("App").gridColumnAlignment(.leading)
                        Text(unit.label); Text("Peak"); Text("Accuracy"); Text(unit.amountLabel); Text("Active"); Text("Sessions")
                    }
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Divider()
                    ForEach(apps) { a in
                        GridRow {
                            Text(a.name).lineLimit(1)
                            Text(unit.format(wpm: a.agg.wpm)).fontWeight(.semibold)
                            Text(unit.format(wpm: a.agg.peakWPM))
                            Text(String(format: "%.1f %%", a.agg.accuracy * 100))
                            Text(unit.formatAmount(chars: a.agg.netChars))
                            Text(formatDuration(a.agg.activeSeconds))
                            Text("\(a.agg.sessions)")
                        }
                        .monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Sessions

struct SessionsPane: View {
    @Environment(AppModel.self) private var model
    let sessions: [TypingSession]
    @State private var selection = Set<Int64>()
    @State private var sortOrder = [KeyPathComparator(\TypingSession.start, order: .reverse)]

    var body: some View {
        let unit = model.unit
        Table(sessions.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Started", value: \.start) { Text($0.start.formatted(date: .abbreviated, time: .shortened)) }
                .width(min: 130, ideal: 150)
            TableColumn("App", value: \.appName)
            TableColumn(unit.label, value: \.wpm) { Text(unit.format(wpm: $0.wpm)).fontWeight(.semibold).monospacedDigit() }
                .width(min: 50, ideal: 60)
            TableColumn("Peak", value: \.peakWPM) { Text(unit.format(wpm: $0.peakWPM)).monospacedDigit() }
                .width(min: 50, ideal: 60)
            TableColumn("Accuracy", value: \.accuracy) { Text(String(format: "%.1f %%", $0.accuracy * 100)).monospacedDigit() }
                .width(min: 60, ideal: 75)
            TableColumn(unit.amountLabel, value: \.chars) { Text(unit.formatAmount(chars: $0.netChars)).monospacedDigit() }
                .width(min: 60, ideal: 80)
            TableColumn("Active", value: \.activeSeconds) { Text(formatDuration($0.activeSeconds)).monospacedDigit() }
                .width(min: 60, ideal: 75)
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            Button(ids.count == 1 ? "Delete Session" : "Delete \(ids.count) Sessions", role: .destructive) {
                model.delete(ids: ids)
            }
        }
        .onDeleteCommand { model.delete(ids: selection) }
        .toolbar {
            ToolbarItem {
                Button { model.exportCSV() } label: { Label("Export as CSV…", systemImage: "square.and.arrow.up") }
                    .help("Export sessions as CSV")
            }
        }
    }
}
