import Cocoa

@MainActor
enum RestoreAssistantLayout {
    static func run() throws {
        for size in [RestoreAssistantController.minimumContentSize, RestoreAssistantController.initialContentSize,
                     NSSize(width: 840, height: 580)] {
            try checkWindow(at: size)
        }
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
        let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
        let point = button.convert(center, to: view.superview)
        guard let hit = view.hitTest(point), hit === button || hit.isDescendant(of: button) else {
            throw failure("Button cannot receive a click: \(title)")
        }
        return button
    }

    private static func visibleViews(in view: NSView) -> [NSView] {
        view.isHidden ? [] : [view] + view.subviews.flatMap(visibleViews)
    }

    private static func waitFor(_ message: String, until condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if !condition() { throw failure(message) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "RestoreAssistantLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
