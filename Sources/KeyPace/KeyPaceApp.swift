import SwiftUI

@main
struct KeyPaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
                .modifier(CapturesOpenWindow())
        }
        .menuBarExtraStyle(.window)

        Window("Statistics", id: StatsWindowController.windowID) {
            StatsView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
                .modifier(CapturesOpenWindow())
        }
        .defaultSize(width: 1000, height: 680)
        .defaultLaunchBehavior(.presented)

        Settings {
            SettingsView()
                .environment(model)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About KeyPace") { About.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Show Statistics") { StatsWindowController.shared.show() }
                    .keyboardShortcut("0")
            }
            CommandGroup(replacing: .importExport) {
                Button("Export Sessions as CSV…") { model.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Tracking") {
                Toggle("Pause Tracking", isOn: $model.paused)
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Picker("Speed Unit", selection: $model.unit) {
                    ForEach(SpeedUnit.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel
    @AppStorage(Prefs.showLiveInMenuBar) private var showLive = true
    var body: some View {
        if !model.hasPermission {
            Image(systemName: "keyboard.badge.exclamationmark")
        } else if model.paused {
            Image(systemName: "pause.circle")
        } else if showLive, let wpm = model.liveWPM {
            Text("\(model.unit.format(wpm: wpm)) \(model.unit.label.lowercased())")
                .monospacedDigit()
        } else {
            Image(systemName: "keyboard")
        }
    }
}
