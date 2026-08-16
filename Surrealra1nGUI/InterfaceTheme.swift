import Cocoa

enum InterfaceTheme {
    static let foreground = NSColor(srgbRed: 215.0 / 255.0, green: 213.0 / 255.0, blue: 214.0 / 255.0, alpha: 1)
    static let muted = NSColor(srgbRed: 164.0 / 255.0, green: 162.0 / 255.0, blue: 163.0 / 255.0, alpha: 1)
    static let accent = NSColor(srgbRed: 42.0 / 255.0, green: 151.0 / 255.0, blue: 241.0 / 255.0, alpha: 1)

    static let heading = NSFont.systemFont(ofSize: 14, weight: .bold)
    static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let bodyStrong = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let detail = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let detailStrong = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let button = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let primaryButton = NSFont.systemFont(ofSize: 13, weight: .bold)
    static let percentage = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
}
