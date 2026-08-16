import Cocoa

@main
final class SurrealApplication: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var restoreAssistant: RestoreAssistantController!

    static func main() {
        let application = NSApplication.shared
        let delegate = SurrealApplication()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if #available(macOS 10.14, *) {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.applicationIconImage = EmojiLogo.image(size: 512)
        configureMainMenu()

        restoreAssistant = RestoreAssistantController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 326),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "surrealra1n"
        window.titleVisibility = .visible
        window.backgroundColor = NSColor(srgbRed: 60.0 / 255.0, green: 59.0 / 255.0, blue: 57.0 / 255.0, alpha: 1)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 480, height: 348)
        window.maxSize = NSSize(width: 480, height: 348)
        window.center()
        window.contentViewController = restoreAssistant
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureMainMenu() {
        let menuBar = NSMenu()
        let applicationItem = NSMenuItem(title: "surrealra1n", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "surrealra1n")
        applicationItem.submenu = applicationMenu
        menuBar.addItem(applicationItem)

        applicationMenu.addItem(withTitle: "About surrealra1n", action: #selector(showAboutPanel), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide surrealra1n", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = applicationMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit surrealra1n", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menuBar
    }

    @objc private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "surrealra1n",
            .applicationVersion: "0.0.3 beta re-release 2",
            .version: "Build 5",
            .credits: NSAttributedString(string: "GUI by chrissyx\nsurrealra1n by pwnerblu")
        ])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreAssistant?.cleanupSession()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard restoreAssistant?.hasRunningOperation == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A surrealra1n operation is still running."
        alert.informativeText = "Closing now can leave the device in Recovery or DFU mode."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Stop and Quit")
        if alert.runModal() == .alertSecondButtonReturn {
            restoreAssistant.stopRunningOperation()
            return .terminateNow
        }
        return .terminateCancel
    }
}
