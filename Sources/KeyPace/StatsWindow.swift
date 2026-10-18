import AppKit
import SwiftUI

/// Opens the SwiftUI "stats" window from anywhere — launch, Dock click, Spotlight, popover —
/// even when the menu bar icon is hidden behind the notch. While the window is open KeyPace
/// shows a Dock icon and a menu bar; when it closes it returns to menu-bar-only.
@MainActor
final class StatsWindowController {
    static let shared = StatsWindowController()
    static let windowID = "stats"

    /// Captured from SwiftUI views (menu bar label, stats window) as soon as one appears.
    var openWindow: OpenWindowAction? {
        didSet {
            if pendingShow, let openWindow {
                pendingShow = false
                openWindow(id: Self.windowID)
                NSApp.activate()
            }
        }
    }
    /// A show() request that arrived before SwiftUI handed over openWindow (early at launch).
    private var pendingShow = false
    private var closeObserver: NSObjectProtocol?

    private init() {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            guard let w = note.object as? NSWindow, StatsWindowController.isStats(w) else { return }
            MainActor.assumeIsolated { NSApp.setActivationPolicy(.accessory) }
        }
    }

    static func isStats(_ w: NSWindow) -> Bool {
        w.identifier?.rawValue.hasPrefix(windowID) == true
    }

    var window: NSWindow? { NSApp.windows.first(where: Self.isStats) }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else if let openWindow {
            openWindow(id: Self.windowID)
        } else {
            pendingShow = true
        }
        NSApp.activate()
    }

    func closeIfOpen() { window?.close() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        MainActor.assumeIsolated {
            _ = AppModel.shared
            // Dev: KeyPace --render-popover out.png renders the menu bar popover to an image.
            if let i = CommandLine.arguments.firstIndex(of: "--render-popover"), i + 1 < CommandLine.arguments.count {
                let host = NSHostingView(rootView: MenuBarView().environment(AppModel.shared))
                host.frame.size = host.fittingSize
                let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.contentView = host
                panel.orderFrontRegardless()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                    exit(0)
                }
                return
            }
            if atLogin {
                // The window scene opens by default; stay quiet when started at login.
                DispatchQueue.main.async { StatsWindowController.shared.closeIfOpen() }
            } else {
                StatsWindowController.shared.show()
            }
        }
    }

    /// Opening the app again (Finder, Spotlight, Dock) while it runs shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { StatsWindowController.shared.show() }
        return false
    }

    /// Always-available fallback when the menu bar icon is hidden (the-menu-bar.md).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let paused = MainActor.assumeIsolated { AppModel.shared.paused }
        menu.addItem(withTitle: paused ? "Resume Tracking" : "Pause Tracking", action: #selector(togglePause), keyEquivalent: "").target = self
        return menu
    }

    @objc private func togglePause() {
        MainActor.assumeIsolated { AppModel.shared.paused.toggle() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Hands SwiftUI's openWindow action to the controller.
struct CapturesOpenWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear { StatsWindowController.shared.openWindow = openWindow }
    }
}
