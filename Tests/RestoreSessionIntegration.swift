import Cocoa

final class SessionRecorder: RestoreSessionDelegate {
    var output = ""
    var stages: [(String, Double)] = []
    var prompts: [RestorePrompt] = []
    var finished = false
    var status: Int32 = -999

    var isChoosingPackageManager: Bool {
        prompts.contains { prompt in
            if case .packageManager = prompt { return true }
            return false
        }
    }

    func restoreSession(_ session: RestoreSession, received text: String) {
        output += text
    }

    func restoreSession(_ session: RestoreSession, didAdvanceTo stage: String, progress: Double) {
        stages.append((stage, progress))
    }

    func restoreSession(_ session: RestoreSession, requests prompt: RestorePrompt) {
        prompts.append(prompt)
        switch prompt {
        case .packageManager: break
        case .rebuildFiles: session.respond("y")
        case .yesNo: session.respond("y")
        case .continueOnly, .recoveryReady, .pwnedReady: session.respond("")
        case .textInput: session.respond("16.4")
        }
    }

    func restoreSession(_ session: RestoreSession, didFinishWith code: Int32) {
        status = code
        finished = true
    }
}

@main
enum RestoreSessionIntegration {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.finishLaunching()
        try testLogWindow()
        try testTerminalOutput()
        try RestoreAssistantLayout.run()
        if CommandLine.arguments.count > 1 {
            try testSourcePreparation(at: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = repository.appendingPathComponent("Tests/Fixtures/surrealra1n.sh")
        try RestoreAssistantLayout.runCompletionFlow(fixture: fixture)
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "Package manager choice: Homebrew", earlyExit: false, packageManagerReply: "n")
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "Package manager choice: MacPorts", earlyExit: false, packageManagerReply: "y")
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "Restore has completed", earlyExit: false)
        try run(fixture: fixture, operation: .restoreWithBlobs, identifier: "iPhone10,6", expected: "Restore has finished", earlyExit: false)
        try run(fixture: fixture, operation: .untethered1033, identifier: "iPhone6,1", expected: "Restore has finished", earlyExit: false)
        try run(fixture: fixture, operation: .justBoot, identifier: "iPhone12,3", expected: "Device should now boot", earlyExit: false)
        // The background menu may write after its parent exits; only require output
        // consumed before the GUI responds to the parent's final Enter prompt.
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "A12/A13 device support is entirely experimental.", earlyExit: true, expectedStatus: 1)
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "Restore has completed", earlyExit: false, heldPipe: true)
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "Restore has completed", earlyExit: false, expectedStatus: 7)
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "Restore has completed", earlyExit: false, legacyMenu: true)
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPad5,1", expected: "Restore has completed", earlyExit: false)
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "returned to its main menu without completing", earlyExit: false, expectedStatus: 1, noDevice: true)
        print("RestoreSession integration tests passed")
    }

    private static func testTerminalOutput() throws {
        let terminal = TerminalOutput()
        terminal.append("One\r\nTwo\r")
        terminal.append("\nThree")
        guard terminal.text == "One\nTwo\nThree" else {
            throw failure("Terminal output lost CRLF line breaks", output: terminal.text)
        }
        terminal.append("\n" + String(repeating: "x", count: 200_000) + "\nDone\n")
        guard terminal.text.hasSuffix("\nDone\n"), terminal.text.count < 200_000 else {
            throw failure("Terminal output did not keep a bounded recent transcript", output: "")
        }
    }

    private static func testSourcePreparation(at url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        let prepared = try RestoreSession().prepareSourceForGUI(source)
        guard prepared.contains("SURREAL_GUI_TARGET_IPSW"),
              prepared.contains("Using the freshly downloaded surrealra1n engine."),
              prepared.contains("SURREAL_GUI_BOOT_VERSION") else {
            throw failure("Current surrealra1n source was not prepared for GUI control", output: "")
        }
    }

    private static func testLogWindow() throws {
        let log = RestoreLogWindow()
        log.clear()
        let firstURL = log.automaticLogURL
        log.append("Starting\rPatching\n\u{001B}[2KRestore 54%\n")
        log.present()
        log.window?.close()
        log.present()
        log.window?.orderOut(nil)
        guard let url = log.automaticLogURL,
              let contents = try? String(contentsOf: url, encoding: .utf8),
              contents.contains("Restore 54%"),
              contents.contains("surrealra1n GUI"),
              contents.contains("macOS:"),
              contents.contains("Session started:") else {
            throw failure("Automatic restore log was not written", output: "")
        }
        log.clear()
        log.append("Second session\n")
        guard let secondURL = log.automaticLogURL,
              secondURL != firstURL,
              let contents = try? String(contentsOf: secondURL, encoding: .utf8),
              contents.contains("Second session"),
              !contents.contains("Restore 54%"),
              let firstContents = try? String(contentsOf: url, encoding: .utf8),
              firstContents.contains("Restore 54%"),
              !firstContents.contains("Second session") else {
            throw failure("Restore sessions did not keep separate logs", output: "")
        }
    }

    private static func run(fixture: URL, operation: RestoreOperation, identifier: String, expected: String, earlyExit: Bool, heldPipe: Bool = false, expectedStatus: Int32 = 0, legacyMenu: Bool = false, noDevice: Bool = false, packageManagerReply: String? = nil) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("surreal-session-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("surrealra1n.sh"))
        let target = root.appendingPathComponent("target.ipsw")
        let base = root.appendingPathComponent("base.ipsw")
        let blob = root.appendingPathComponent("ticket.shsh2")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        FileManager.default.createFile(atPath: base.path, contents: Data())
        FileManager.default.createFile(atPath: blob.path, contents: Data())

        if earlyExit { setenv("SURREAL_TEST_EARLY_EXIT", "1", 1) }
        if heldPipe { setenv("SURREAL_TEST_HELD_PIPE", "1", 1) }
        if expectedStatus == 7 { setenv("SURREAL_TEST_FAIL_AFTER_COMPLETION", "1", 1) }
        if legacyMenu { setenv("SURREAL_TEST_LEGACY_MENU", "1", 1) }
        if noDevice { setenv("SURREAL_TEST_NO_DEVICE", "1", 1) }
        setenv("SURREAL_TEST_DEVICE_IDENTIFIER", identifier, 1)
        if packageManagerReply != nil { setenv("SURREAL_TEST_PACKAGE_MANAGER_PROMPT", "1", 1) }
        defer {
            unsetenv("SURREAL_TEST_EARLY_EXIT")
            unsetenv("SURREAL_TEST_HELD_PIPE")
            unsetenv("SURREAL_TEST_FAIL_AFTER_COMPLETION")
            unsetenv("SURREAL_TEST_LEGACY_MENU")
            unsetenv("SURREAL_TEST_NO_DEVICE")
            unsetenv("SURREAL_TEST_DEVICE_IDENTIFIER")
            unsetenv("SURREAL_TEST_PACKAGE_MANAGER_PROMPT")
        }

        let session = RestoreSession()
        defer { if session.isRunning { session.cancel() } }
        let recorder = SessionRecorder()
        session.delegate = recorder
        try session.start(
            engine: root,
            target: target,
            base: base,
            shsh: blob,
            bootVersion: "16.4",
            deviceIdentifier: identifier,
            operation: operation
        )

        let started = Date()
        let deadline = started.addingTimeInterval(8)
        if let packageManagerReply = packageManagerReply {
            while !recorder.isChoosingPackageManager && !recorder.finished && Date() < deadline
                && RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) {}
            guard recorder.isChoosingPackageManager, session.isRunning,
                  !recorder.output.contains("Package manager choice:") else {
                throw failure("Session did not wait for a package manager choice", output: recorder.output)
            }
            session.respond(packageManagerReply)
        }
        while !recorder.finished && RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) && Date() < deadline {}
        guard recorder.finished else { throw failure("Session timed out", output: recorder.output) }
        guard recorder.status == expectedStatus else {
            throw failure("Session exited with \(recorder.status), expected \(expectedStatus)", output: recorder.output)
        }
        guard recorder.output.contains(expected) else { throw failure("Missing expected output: \(expected)", output: recorder.output) }
        if heldPipe && Date().timeIntervalSince(started) >= 1.5 {
            throw failure("Session completion waited for an inherited output pipe", output: recorder.output)
        }
        if expectedStatus == 0 && operation == .tetheredRestore {
            guard recorder.stages.contains(where: { $0.0 == "Finalizing restore and boot files…" && $0.1 < 1 }) else {
                throw failure("The session did not distinguish reported progress from final completion", output: recorder.output)
            }
        }
    }

    private static func failure(_ message: String, output: String) -> NSError {
        NSError(domain: "RestoreSessionIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\(output)"])
    }
}
