import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.pauseThreshold) private var pauseThreshold = 2.0
    @AppStorage(Prefs.sessionTimeout) private var sessionTimeout = 20.0
    @AppStorage(Prefs.minChars) private var minChars = 30
    @AppStorage(Prefs.excludedApps) private var excludedApps = ""
    @AppStorage(Prefs.showLiveInMenuBar) private var showLive = true
    @State private var launchAtLogin = false
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Display") {
                Picker("Speed unit", selection: $model.unit) {
                    ForEach(SpeedUnit.allCases) { Text($0.longLabel).tag($0) }
                }
                Toggle("Show live speed in the menu bar while typing", isOn: $showLive)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in model.launchAtLogin = on }
            }

            Section {
                LabeledContent("Pause threshold") {
                    Stepper("\(pauseThreshold, specifier: "%.1f") s", value: $pauseThreshold, in: 0.5...10, step: 0.5)
                }
                LabeledContent("End session after idle") {
                    Stepper("\(Int(sessionTimeout)) s", value: $sessionTimeout, in: 5...300, step: 5)
                }
                LabeledContent("Minimum length to save") {
                    Stepper("\(minChars) characters (\(minChars / 5) words)", value: $minChars, in: 5...500, step: 5)
                }
            } header: {
                Text("Measuring")
            } footer: {
                Text("Gaps longer than the pause threshold count as thinking time and are not part of your speed. A session ends when you switch apps or stop typing for the idle time.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $excludedApps)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 90)
                Button("Exclude the app I used last") {
                    if let id = model.sessions.last?.appBundleID, !excludedApps.contains(id) {
                        excludedApps += (excludedApps.isEmpty ? "" : "\n") + id
                    }
                }
                .disabled(model.sessions.isEmpty)
            } header: {
                Text("Ignored apps (one bundle ID per line)")
            } footer: {
                Text("Password fields are never seen anyway: macOS blocks key monitoring while Secure Input is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Privacy & Data") {
                LabeledContent("Input Monitoring") {
                    if model.hasPermission {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access") { model.requestPermission() }
                    }
                }
                Text("KeyPace only counts keystrokes (character vs. backspace) and timing. The keys themselves are never stored or sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Database") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.url]) }
                }
                HStack {
                    Button("Export CSV…") { model.exportCSV() }
                    Spacer()
                    Button("Delete All Sessions…", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onAppear {
            launchAtLogin = model.launchAtLogin
            NSApp.activate()
        }
        .confirmationDialog("Delete all \(model.sessions.count) recorded sessions?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) { model.deleteAll() }
        } message: {
            Text("This cannot be undone.")
        }
    }
}
