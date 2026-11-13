import Cocoa

@MainActor
enum RestoreAssistantLayout {
    static func run() throws {
        for size in [RestoreAssistantController.minimumContentSize, RestoreAssistantController.initialContentSize,
                     NSSize(width: 840, height: 580)] {
            try checkWindow(at: size)
        }
    }

    static func runCompletionFlow(fixture: URL) throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("surreal-assistant-test-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try files.copyItem(at: fixture, to: root.appendingPathComponent("surrealra1n.sh"))
        let target = root.appendingPathComponent("target.ipsw")
        let base = root.appendingPathComponent("base.ipsw")
        try Data().write(to: target)
        try Data().write(to: base)
        setenv("SURREAL_TEST_BOOT_FILES", "1", 1)
        setenv("SURREAL_TEST_HELD_PIPE", "1", 1)
        setenv("SURREAL_TEST_PACKAGE_MANAGER_PROMPT", "1", 1)
        setenv("SURREAL_TEST_DEVICE_IDENTIFIER", "iPhone10,3", 1)
        defer {
            unsetenv("SURREAL_TEST_BOOT_FILES")
            unsetenv("SURREAL_TEST_HELD_PIPE")
            unsetenv("SURREAL_TEST_PACKAGE_MANAGER_PROMPT")
            unsetenv("SURREAL_TEST_DEVICE_IDENTIFIER")
        }

        var picks = [target, base]
        let assistant = RestoreAssistantController(pickFirmware: { _, _, pick in
            if !picks.isEmpty { pick(picks.removeFirst()) }
        })
        let size = RestoreAssistantController.minimumContentSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        window.contentViewController = assistant
        window.setContentSize(size)
        window.orderBack(nil)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            assistant.stopRunningOperation()
            window.close()
        }
        let view = assistant.view
        let device = ConnectedDevice(name: "Test iPhone", identifier: "iPhone10,3", ecid: "4660", mode: "Normal")
        assistant.deviceDidChange(to: device)
        guard hasButton("Loading…", in: view, enabled: false) else { throw failure("Setup did not show that the engine was loading") }
        assistant.engineDidPrepare(.success(root))

        try clickableButton("Start", in: view).performClick(nil)
        try clickableButton("Restore tethered", in: view).performClick(nil)
        try clickableButton("Continue", in: view).performClick(nil)
        try chooseFirmware(in: view)
        try clickableButton("Continue", in: view).performClick(nil)
        try confirmRestore(in: window, view: view)
        try waitFor("The package manager choice did not appear") { hasButton("Keep Homebrew", in: view) }
        try clickableButton("Keep Homebrew", in: view).performClick(nil)
        try waitFor("The restore never reached finalization") { hasText("Finalizing restore and boot files…", in: view) }
        guard !hasButton("Just Boot", in: view), assistant.hasRunningOperation else {
            throw failure("The result appeared before the boot files were finished")
        }
        assistant.deviceDidChange(to: nil)
        try Data().write(to: root.appendingPathComponent(".finish-fixture"))
        try waitFor("The finished restore did not show its next actions") { hasText("Restore complete", in: view) }
        _ = try clickableButton("Done", in: view)
        try showAndCloseLogs(in: view, containing: "Simulated boot files are ready")
        try clickableButton("Just Boot", in: view).performClick(nil)
        guard hasText("Reconnect the device you restored to continue.", in: view),
              visibleViews(in: view).compactMap({ $0 as? NSPopUpButton }).first?.titleOfSelectedItem == "16.4",
              hasButton("Continue", in: view, enabled: false) else {
            throw failure("The boot picker lost the restored device or its saved version during reconnect")
        }
        _ = try clickableButton("Import Bootchain…", in: view)
        try clickableButton("Back", in: view).performClick(nil)
        try clickableButton("Just Boot", in: view).performClick(nil)
        assistant.deviceDidChange(to: ConnectedDevice(name: device.name, identifier: device.identifier, ecid: "0x5678", mode: "Recovery"))
        guard hasButton("Continue", in: view, enabled: false) else { throw failure("The picker accepted a different phone of the same model") }
        assistant.deviceDidChange(to: ConnectedDevice(name: device.name, identifier: device.identifier, ecid: "0x1234", mode: "Recovery"))
        try clickableButton("Continue", in: view).performClick(nil)
        try clickableButton("Start Boot", in: view).performClick(nil)
        try waitFor("The boot session did not show the next choice") { hasButton("Use MacPorts", in: view) }
        try clickableButton("Use MacPorts", in: view).performClick(nil)
        try waitFor("Just Boot never finished") { hasText("All done", in: view) }
        try showAndCloseLogs(in: view, containing: "Device should now boot")
        try clickableButton("Done", in: view).performClick(nil)
        guard hasText("Welcome to surrealra1n!", in: view) else { throw failure("Done did not return to the welcome screen") }

        try Data().write(to: root.appendingPathComponent(".fail-fixture"))
        try clickableButton("Start", in: view).performClick(nil)
        try clickableButton("Restore tethered", in: view).performClick(nil)
        try clickableButton("Continue", in: view).performClick(nil)
        try clickableButton("Continue", in: view).performClick(nil)
        try confirmRestore(in: window, view: view)
        try waitFor("The second restore did not reach the package manager choice") { hasButton("Keep Homebrew", in: view) }
        try clickableButton("Keep Homebrew", in: view).performClick(nil)
        try waitFor("A late engine error did not reach the result screen") { hasText("The operation stopped", in: view) }
        guard !hasButton("Just Boot", in: view),
              hasText("surrealra1n exited with code 7. Open the log for the exact failure.", in: view) else {
            throw failure("A late failure was reported as a successful restore")
        }
        try clickableButton("Done", in: view).performClick(nil)
        guard hasText("Welcome to surrealra1n!", in: view) else { throw failure("The failure result had no working way back") }
        NSApp.windows.filter { $0.title == "surrealra1n Log" }.forEach { $0.orderOut(nil) }
        print("Wizard click-through passed: setup → restore → reconnect → Just Boot → Done, and late failure → Done")
    }

    private static func chooseFirmware(in view: NSView) throws {
        view.layoutSubtreeIfNeeded()
        let buttons = visibleViews(in: view).compactMap { $0 as? NSButton }.filter { $0.title == "Choose…" }
        guard buttons.count == 2 else { throw failure("Both firmware choices were not visible") }
        try assertClickable(buttons[0], in: view)
        buttons[0].performClick(nil)
        view.layoutSubtreeIfNeeded()
        guard let base = visibleViews(in: view).compactMap({ $0 as? NSButton }).filter({ $0.title == "Choose…" }).last else {
            throw failure("The signed base firmware choice was missing")
        }
        try assertClickable(base, in: view)
        base.performClick(nil)
    }

    private static func confirmRestore(in window: NSWindow, view: NSView) throws {
        try clickableButton("Start Restore", in: view).performClick(nil)
        guard let sheet = window.attachedSheet, let content = sheet.contentView else {
            throw failure("Start Restore did not open its confirmation")
        }
        try clickableButton("Start Restore", in: content).performClick(nil)
    }

    private static func showAndCloseLogs(in view: NSView, containing expected: String) throws {
        try clickableButton("Show Logs", in: view).performClick(nil)
        guard let log = NSApp.windows.first(where: { $0.title == "surrealra1n Log" && $0.isVisible }),
              let content = log.contentView,
              visibleViews(in: content).compactMap({ $0 as? NSTextView }).contains(where: { $0.string.contains(expected) }) else {
            throw failure("Show Logs did not display the final output: \(expected)")
        }
        log.close()
    }

    private static func hasText(_ text: String, in view: NSView) -> Bool {
        visibleViews(in: view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == text }
    }

    private static func hasButton(_ title: String, in view: NSView, enabled: Bool = true) -> Bool {
        visibleViews(in: view).compactMap { $0 as? NSButton }.contains { $0.title == title && $0.isEnabled == enabled }
    }

    private static func checkWindow(at size: NSSize) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentMinSize = RestoreAssistantController.minimumContentSize
        let assistant = RestoreAssistantController()
        window.contentViewController = assistant
        window.setContentSize(size)
        defer { window.close() }
        let view = assistant.view

        try clickableButton("Options", in: view).performClick(nil)
        _ = try clickableButton("Change…", in: view)
        try clickableButton("Back", in: view).performClick(nil)

        let session = RestoreSession()
        assistant.restoreSession(session, requests: .packageManager)
        assistant.restoreSession(session, didAdvanceTo: "DFU: Simulated status update", progress: 0.02)
        let homebrew = try clickableButton("Keep Homebrew", in: view)
        let macPorts = try clickableButton("Use MacPorts", in: view)
        _ = try clickableButton("Show Logs", in: view)
        _ = try clickableButton("Cancel", in: view)
        (size == RestoreAssistantController.minimumContentSize ? homebrew : macPorts).performClick(nil)

        view.layoutSubtreeIfNeeded()
        guard let console = visibleViews(in: view).compactMap({ $0 as? LogTranscriptView }).first,
              let text = console.documentView as? NSTextView else {
            throw failure("The progress console was missing")
        }
        let originalFrame = console.frame
        assistant.restoreSession(session, received: (0..<140).map { "Diagnostic line \($0)\r\n" }.joined())
        try waitFor("The console did not display its output") { text.string.contains("Diagnostic line 139") }
        guard console.documentVisibleRect.minY > 20 else { throw failure("The console did not follow new output") }
        console.contentView.scroll(to: .zero)
        console.reflectScrolledClipView(console.contentView)
        text.setSelectedRange(NSRange(location: 0, length: 10))

        for index in 1...20 {
            assistant.restoreSession(session, didAdvanceTo: String(repeating: "Updating ", count: index), progress: Double(index) / 25)
            assistant.restoreSession(session, received: "Later update \(index)\n")
        }
        try waitFor("The console did not display the latest update") { text.string.contains("Later update 20") }
        view.layoutSubtreeIfNeeded()
        guard visibleViews(in: view).contains(where: { $0 === console }) else { throw failure("Live output replaced the console") }
        guard view.bounds.size == size, console.frame == originalFrame else {
            throw failure("Live output resized the window or console: \(view.bounds.size), \(console.frame), expected \(size), \(originalFrame)")
        }
        guard console.documentVisibleRect.minY < 5, text.selectedRange() == NSRange(location: 0, length: 10) else {
            throw failure("Live output interrupted reading: scroll position \(console.documentVisibleRect.minY), selection \(text.selectedRange())")
        }

        let prompt = String(repeating: "Read this diagnostic information before choosing an answer.\n", count: 50)
        assistant.restoreSession(session, requests: .yesNo(prompt))
        _ = try clickableButton("Yes", in: view)
        _ = try clickableButton("Cancel", in: view)
        guard let scroll = visibleViews(in: view).compactMap({ $0 as? NSScrollView }).first,
              let promptView = scroll.documentView as? NSTextView, promptView.string == prompt,
              scroll.hasVerticalScroller, scroll.frame.height > 100 else {
            throw failure("A long prompt was not readable in a scroll view")
        }
        try clickableButton("No", in: view).performClick(nil)
        _ = try clickableButton("Show Logs", in: view)
    }

    private static func clickableButton(_ title: String, in view: NSView) throws -> NSButton {
        view.layoutSubtreeIfNeeded()
        guard let button = visibleViews(in: view).compactMap({ $0 as? NSButton }).first(where: { $0.title == title }),
              button.isEnabled else {
            throw failure("Missing or disabled button: \(title)")
        }
        try assertClickable(button, in: view)
        return button
    }

    private static func assertClickable(_ button: NSButton, in view: NSView) throws {
        let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
        let point = button.convert(center, to: view.superview)
        guard let hit = view.hitTest(point), hit === button || hit.isDescendant(of: button) else {
            throw failure("Button cannot receive a click: \(button.title)")
        }
    }

    private static func visibleViews(in view: NSView) -> [NSView] {
        view.isHidden ? [] : [view] + view.subviews.flatMap(visibleViews)
    }

    private static func waitFor(_ message: String, until condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if !condition() { throw failure(message) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "RestoreAssistantLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
