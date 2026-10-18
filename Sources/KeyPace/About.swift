import AppKit

/// The standard About panel, with the repository link and license in the credits.
enum About {
    static let repositoryURL = URL(string: "https://github.com/kaichn/keypace")!
    static let licenseURL = URL(string: "https://github.com/kaichn/keypace/blob/main/LICENSE")!

    @MainActor static func show() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        let credits = NSMutableAttributedString(
            string: "Measures your typing speed while you work.\nCounts keystrokes, never stores text.\n\n",
            attributes: base)
        credits.append(link("github.com/kaichn/keypace", to: repositoryURL, base: base))
        credits.append(NSAttributedString(string: "\nReleased under the ", attributes: base))
        credits.append(link("MIT License", to: licenseURL, base: base))

        // A menu bar app must come to the front, or the panel opens behind other windows.
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static func link(_ text: String, to url: URL, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attributes = base
        attributes[.link] = url
        attributes[.foregroundColor] = NSColor.linkColor
        return NSAttributedString(string: text, attributes: attributes)
    }
}
