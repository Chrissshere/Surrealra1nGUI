import Cocoa

final class SessionRecorder: RestoreSessionDelegate {
    var output = ""
    var stages: [(String, Double)] = []
    var prompts: [RestorePrompt] = []
    var finished = false
    var status: Int32 = -999

    func restoreSession(_ session: RestoreSession, received text: String) {
        output += text
    }

    func restoreSession(_ session: RestoreSession, didAdvanceTo stage: String, progress: Double) {
        stages.append((stage, progress))
    }

    func restoreSession(_ session: RestoreSession, requests prompt: RestorePrompt) {
        prompts.append(prompt)
        switch prompt {
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
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.finishLaunching()
        try testLogWindow()
        if CommandLine.arguments.count > 1 {
            try testSourcePreparation(at: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = repository.appendingPathComponent("Tests/Fixtures/surrealra1n.sh")
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "Restore has finished", earlyExit: false)
        try run(fixture: fixture, operation: .restoreWithBlobs, identifier: "iPhone10,6", expected: "Restore has finished", earlyExit: false)
        try run(fixture: fixture, operation: .untethered1033, identifier: "iPhone6,1", expected: "Restore has finished", earlyExit: false)
        try run(fixture: fixture, operation: .justBoot, identifier: "iPhone12,3", expected: "Device should now boot", earlyExit: false)
        try run(fixture: fixture, operation: .tetheredRestore, identifier: "iPhone12,3", expected: "1. Restore (with SHSH blobs)", earlyExit: true)
        print("RestoreSession integration tests passed")
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
        log.append("Starting\rPatching\n\u{001B}[2KRestore 54%\n")
        log.present()
        log.window?.close()
        log.present()
        log.window?.orderOut(nil)
        guard let url = log.automaticLogURL,
              let contents = try? String(contentsOf: url, encoding: .utf8),
              contents.contains("Restore 54%") else {
            throw failure("Automatic restore log was not written", output: "")
        }
    }

    private static func run(fixture: URL, operation: RestoreOperation, identifier: String, expected: String, earlyExit: Bool) throws {
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
        defer { unsetenv("SURREAL_TEST_EARLY_EXIT") }

        let session = RestoreSession()
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

        let deadline = Date().addingTimeInterval(8)
        while !recorder.finished && RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) && Date() < deadline {}
        guard recorder.finished else { throw failure("Session timed out", output: recorder.output) }
        guard recorder.status == 0 else { throw failure("Session exited with \(recorder.status)", output: recorder.output) }
        guard recorder.output.contains(expected) else { throw failure("Missing expected output: \(expected)", output: recorder.output) }
        if !earlyExit && operation == .tetheredRestore {
            guard recorder.stages.contains(where: { $0.0 == "Restore complete" && $0.1 == 1 }) else {
                throw failure("Restore progress did not complete", output: recorder.output)
            }
        }
    }

    private static func failure(_ message: String, output: String) -> NSError {
        NSError(domain: "RestoreSessionIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\(output)"])
    }
}
