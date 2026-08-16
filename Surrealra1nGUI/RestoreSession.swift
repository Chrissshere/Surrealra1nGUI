import Cocoa

enum RestoreOperation {
    case restoreWithBlobs
    case tetheredRestore
    case untethered1033
    case justBoot
}

enum RestorePrompt {
    case recoveryReady
    case pwnedReady
    case rebuildFiles
    case yesNo(String)
    case continueOnly(String)
    case textInput(String)
}

protocol RestoreSessionDelegate: AnyObject {
    func restoreSession(_ session: RestoreSession, received text: String)
    func restoreSession(_ session: RestoreSession, didAdvanceTo stage: String, progress: Double)
    func restoreSession(_ session: RestoreSession, requests prompt: RestorePrompt)
    func restoreSession(_ session: RestoreSession, didFinishWith code: Int32)
}

final class RestoreSession {
    weak var delegate: RestoreSessionDelegate?

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var automationBuffer = ""
    private var menuStep = 0
    private var awaitingUser = false
    private var maximumProgress = 0.0
    private var temporaryScript: URL?
    private var environmentFile: URL?
    private var askpassFile: URL?
    private var operation: RestoreOperation = .tetheredRestore
    private var dfuPhase = ""

    var isRunning: Bool { return process?.isRunning == true }

    func start(engine: URL, target: URL?, base: URL?, shsh: URL?, bootVersion: String?, deviceIdentifier: String, operation: RestoreOperation) throws {
        guard !isRunning else { return }
        if operation == .restoreWithBlobs && Self.isA12OrA13(deviceIdentifier) {
            throw NSError(
                domain: "Surrealra1nGUI",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "SHSH restores are unavailable for A12 and A13 devices."]
            )
        }
        let sourceURL = engine.appendingPathComponent("surrealra1n.sh")
        let originalSource = try String(contentsOf: sourceURL, encoding: .utf8)
        let source = try prepareSourceForGUI(originalSource)

        let sessionID = UUID().uuidString
        let scriptURL = engine.appendingPathComponent(".surrealra1n-gui-\(sessionID).sh")
        try source.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        temporaryScript = scriptURL

        let envURL = FileManager.default.temporaryDirectory.appendingPathComponent("surrealra1n-gui-env-\(sessionID).sh")
        let shellEnvironment = """
read() {
    local prompt=""
    local arguments=()
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-p" ]]; then
            shift
            prompt="${1-}"
        else
            arguments+=("$1")
        fi
        shift
    done
    if [[ -n "$prompt" ]]; then
        printf '%s' "$prompt" >&2
    fi
    builtin read "${arguments[@]}"
}
sudo() { command /usr/bin/sudo -A "$@"; }

"""
        try shellEnvironment.write(to: envURL, atomically: true, encoding: .utf8)
        environmentFile = envURL

        let task = Process()
        let stdin = Pipe()
        let output = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = [scriptURL.path]
        task.currentDirectoryPath = engine.path
        task.standardInput = stdin
        task.standardOutput = output
        task.standardError = output

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["BASH_ENV"] = envURL.path
        env["SURREAL_GUI_TARGET_IPSW"] = target?.path ?? ""
        env["SURREAL_GUI_BASE_IPSW"] = base?.path ?? ""
        env["SURREAL_GUI_SHSH"] = shsh?.path ?? ""
        env["SURREAL_GUI_BOOT_VERSION"] = bootVersion ?? ""
        if let bundledAskpass = Bundle.main.url(forResource: "surreal-askpass", withExtension: "sh") {
            let askpass = FileManager.default.temporaryDirectory.appendingPathComponent("surrealra1n-askpass-\(sessionID).sh")
            try FileManager.default.copyItem(at: bundledAskpass, to: askpass)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
            askpassFile = askpass
            env["SUDO_ASKPASS"] = askpass.path
        }
        let brewPaths = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:"
        env["PATH"] = brewPaths + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        task.environment = env

        self.operation = operation
        process = task
        inputPipe = stdin
        outputPipe = output
        automationBuffer = ""
        menuStep = 0
        awaitingUser = false
        maximumProgress = 0
        dfuPhase = ""

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text) }
        }
        task.terminationHandler = { [weak self] task in
            output.fileHandleForReading.readabilityHandler = nil
            let remaining = output.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                if !remaining.isEmpty { self?.consume(String(decoding: remaining, as: UTF8.self)) }
                self?.cleanup()
                if let self = self { self.delegate?.restoreSession(self, didFinishWith: task.terminationStatus) }
            }
        }

        delegate?.restoreSession(self, didAdvanceTo: "Starting surrealra1n", progress: 0.01)
        task.launch()
    }

    func prepareSourceForGUI(_ source: String) throws -> String {
        var prepared = try injectingGUIUpdateBypass(into: source)
        prepared = try injectingGUIFilePicker(into: prepared)
        prepared = try injectingGUIBootSelection(into: prepared)
        return prepared
    }

    private static func isA12OrA13(_ identifier: String) -> Bool {
        return identifier.hasPrefix("iPhone11,")
            || identifier.hasPrefix("iPhone12,")
            || identifier.hasPrefix("iPad11,")
    }

    func respond(_ response: String) {
        guard let data = (response + "\n").data(using: .utf8) else { return }
        inputPipe?.fileHandleForWriting.write(data)
        awaitingUser = false
        automationBuffer = ""
    }

    func cancel() {
        process?.interrupt()
    }

    private func consume(_ text: String) {
        delegate?.restoreSession(self, received: text)
        automationBuffer += text.replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        if automationBuffer.count > 16_000 {
            automationBuffer = String(automationBuffer.suffix(12_000))
        }
        updateProgress(from: text)
        updateDFUGuide(from: text)
        handleAutomation()
    }

    private func handleAutomation() {
        guard !awaitingUser else { return }
        let b = automationBuffer

        if b.contains("Would you like to update now? (y/n):") {
            sendAutomated("n")
        } else if containsAll(["1. Downgrade Options", "2. Misc Utilities", "4. Exit"], in: b) {
            sendAutomated("1")
        } else if b.contains("A12/A13 device support is entirely experimental") && b.contains("Press enter to continue") {
            sendAutomated("")
        } else if containsAll(["1. Restore (with SHSH blobs)", "2. Restore (Tethered)", "4. Just Boot", "5. Back"], in: b) {
            switch operation {
            case .restoreWithBlobs: sendAutomated("1")
            case .tetheredRestore: sendAutomated("2")
            case .untethered1033: sendAutomated("3")
            case .justBoot: sendAutomated("4")
            }
        } else if operation == .tetheredRestore && containsAll(["1. Select Target IPSW", "2. Select Base IPSW", "3. Start Restore", "4. Back"], in: b) {
            menuStep += 1
            if menuStep == 1 { sendAutomated("1") }
            else if menuStep == 2 { sendAutomated("2") }
            else { sendAutomated("3") }
        } else if operation == .restoreWithBlobs && containsAll(["1. Select Target IPSW", "2. Select SHSH", "3. Start Restore", "4. Back"], in: b) {
            menuStep += 1
            if menuStep == 1 { sendAutomated("1") }
            else if menuStep == 2 { sendAutomated("2") }
            else { sendAutomated("3") }
        } else if operation == .untethered1033 && containsAll(["1. Select 10.3.3 IPSW", "2. Start Restore", "3. Back"], in: b) {
            menuStep += 1
            sendAutomated(menuStep == 1 ? "1" : "2")
        } else if b.localizedCaseInsensitiveContains("Input the version you'd like to boot:") {
            request(.textInput("Enter the installed tethered iOS version to boot."))
        } else if b.contains("Would you like instructions on how to do this? (y/n):") {
            delegate?.restoreSession(self, didAdvanceTo: "Entering DFU mode", progress: max(maximumProgress, 0.08))
            sendAutomated("y")
        } else if b.contains("Press enter to continue once Device is in Recovery") {
            request(.recoveryReady)
        } else if b.localizedCaseInsensitiveContains("Press enter to continue once device is pwned successfully") {
            request(.pwnedReady)
        } else if b.contains("Would you like to make new ones? (y/n):") {
            request(.rebuildFiles)
        } else if b.contains("Since iOS 16 should activate normally") && b.contains("Press enter to continue") {
            sendAutomated("")
        } else if b.contains("Press enter to continue") {
            request(.continueOnly(lastMeaningfulLine(in: b)))
        } else if b.range(of: #"(?:Would you like|Are you sure)[^\n]*\([yn]/[yn]\):"#, options: [.regularExpression, .caseInsensitive]) != nil {
            request(.yesNo(lastMeaningfulLine(in: b)))
        }
    }

    private func sendAutomated(_ value: String) {
        respond(value)
    }

    private func containsAll(_ values: [String], in text: String) -> Bool {
        return values.allSatisfy { text.contains($0) }
    }

    private func request(_ prompt: RestorePrompt) {
        awaitingUser = true
        automationBuffer = ""
        delegate?.restoreSession(self, requests: prompt)
    }

    private func lastMeaningfulLine(in text: String) -> String {
        return text.split(separator: "\n").suffix(4).joined(separator: "\n")
    }

    private func updateProgress(from text: String) {
        let lower = text.lowercased()
        if operation == .justBoot {
            updateBootProgress(from: lower)
            return
        }
        var stage: String?
        var floor = maximumProgress

        if lower.contains("checking for dfu") || lower.contains("instructions will begin") { stage = "Entering DFU mode"; floor = 0.08 }
        if lower.contains("device is pwned") { stage = "Device exploited"; floor = 0.14 }
        if lower.contains("making new ones") || lower.contains("archive:") { stage = "Building restore image"; floor = 0.20 }
        if lower.contains("patching") { stage = "Patching firmware"; floor = 0.42 }
        if lower.contains("adding:") { stage = "Packaging custom IPSW"; floor = 0.53 }
        if lower.contains("sending ibec") || lower.contains("sending restore ramdisk") { stage = "Starting restore environment"; floor = 0.58 }
        if lower.contains("sending filesystem") || lower.contains("restoring") { stage = "Restoring system"; floor = 0.62 }
        if lower.contains("updating baseband") { stage = "Updating baseband"; floor = 0.82 }
        if lower.contains("fdr") && maximumProgress >= 0.62 { stage = "Finalizing device restore"; floor = 0.88 }
        if lower.contains("sealing system volume") { stage = "Sealing system volume"; floor = 0.95 }
        if lower.contains("status: restore finished") || lower.contains("restore has finished") { stage = "Restore complete"; floor = 1.0 }

        if maximumProgress >= 0.62,
           let componentProgress = reportedPercentage(in: text) {
            stage = stage ?? "Restoring system"
            floor = max(floor, 0.62 + min(componentProgress, 100) / 100 * 0.37)
        }

        maximumProgress = max(maximumProgress, floor)
        if let stage = stage { delegate?.restoreSession(self, didAdvanceTo: stage, progress: maximumProgress) }
    }

    private func updateBootProgress(from lower: String) {
        var stage: String?
        var floor = maximumProgress
        if lower.contains("checking for dfu") || lower.contains("instructions will begin") { stage = "Entering DFU mode"; floor = 0.08 }
        if lower.contains("device is pwned") { stage = "Device is pwned"; floor = 0.35 }
        if lower.contains("sending ibss") { stage = "Sending iBSS"; floor = 0.70 }
        if lower.contains("sending ibec") { stage = "Sending iBEC"; floor = 0.78 }
        if lower.contains("sending devicetree") { stage = "Sending DeviceTree"; floor = 0.84 }
        if lower.contains("sending trustcache") { stage = "Sending trustcache"; floor = 0.90 }
        if lower.contains("sending kernelcache") { stage = "Sending Kernelcache"; floor = 0.96 }
        if lower.contains("device should now boot") { stage = "Device should now boot"; floor = 1.0 }
        maximumProgress = max(maximumProgress, floor)
        if let stage = stage { delegate?.restoreSession(self, didAdvanceTo: stage, progress: maximumProgress) }
    }

    private func reportedPercentage(in text: String) -> Double? {
        if let range = text.range(of: #"[0-9]+(?:\.[0-9]+)?\s*%"#, options: .regularExpression) {
            let candidate = String(text[range])
            if let number = candidate.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) {
                return Double(String(candidate[number]))
            }
        }
        guard let range = text.range(of: #"(?:progress|percentage)\s*[:=]?\s*[0-9]+(?:\.[0-9]+)?"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let candidate = String(text[range])
        guard let number = candidate.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) else { return nil }
        return Double(String(candidate[number]))
    }

    private func updateDFUGuide(from text: String) {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.localizedCaseInsensitiveContains("Instructions will begin in") {
                dfuPhase = "Get ready"
                delegate?.restoreSession(self, didAdvanceTo: "DFU: Get ready", progress: max(maximumProgress, 0.08))
            } else if line.localizedCaseInsensitiveContains("Hold volume down + power buttons") {
                dfuPhase = "Hold Side + Volume Down"
                delegate?.restoreSession(self, didAdvanceTo: "DFU: Hold Side + Volume Down", progress: max(maximumProgress, 0.09))
            } else if line.localizedCaseInsensitiveContains("Hold power + home buttons") {
                dfuPhase = "Hold Power + Home"
                delegate?.restoreSession(self, didAdvanceTo: "DFU: Hold Power + Home", progress: max(maximumProgress, 0.09))
            } else if line.localizedCaseInsensitiveContains("Release the power button") {
                if line.localizedCaseInsensitiveContains("home button") {
                    dfuPhase = "Release Power, keep holding Home"
                    delegate?.restoreSession(self, didAdvanceTo: "DFU: Release Power, keep holding Home", progress: max(maximumProgress, 0.10))
                } else {
                    dfuPhase = "Release Side, keep holding Volume Down"
                    delegate?.restoreSession(self, didAdvanceTo: "DFU: Release Side, keep holding Volume Down", progress: max(maximumProgress, 0.10))
                }
            } else if !dfuPhase.isEmpty, Int(line) != nil {
                delegate?.restoreSession(self, didAdvanceTo: "DFU: \(dfuPhase)  (\(line))", progress: max(maximumProgress, 0.10))
            } else if line.localizedCaseInsensitiveContains("Device is now in DFU mode") || line.localizedCaseInsensitiveContains("Device is pwned") {
                dfuPhase = ""
                delegate?.restoreSession(self, didAdvanceTo: "DFU mode detected", progress: max(maximumProgress, 0.14))
            }
        }
    }

    private func injectingGUIFilePicker(into source: String) throws -> String {
        guard let start = source.range(of: "pick_file() {")?.lowerBound,
              let endMarker = source.range(of: "\n\n# Dependency check", range: start..<source.endIndex)?.lowerBound else {
            throw NSError(domain: "Surrealra1nGUI", code: 2, userInfo: [NSLocalizedDescriptionKey: "This surrealra1n version has an unsupported file-picker layout."])
        }

        let replacement = """
pick_file() {
    local p
    if [[ -n \"$SURREAL_GUI_TARGET_IPSW\" && \"$1\" == \"Select an IPSW file\" ]]; then
        echo \"$SURREAL_GUI_TARGET_IPSW\"
        return
    fi
    if [[ -n \"$SURREAL_GUI_BASE_IPSW\" && \"$1\" == Select\\ iOS*IPSW\\ file ]]; then
        echo \"$SURREAL_GUI_BASE_IPSW\"
        return
    fi
    if [[ -n \"$SURREAL_GUI_SHSH\" && \"$1\" == \"Select an SHSH2 file\" ]]; then
        echo \"$SURREAL_GUI_SHSH\"
        return
    fi
    p=$($zenity --file-selection --title=\"$1\" 2>/dev/null)
    if [[ -z \"$p\" ]]; then
        read -e -r -p \"$1 - enter absolute path (blank to cancel): \" p </dev/tty
    fi
    echo \"$p\"
}
"""
        var result = source
        result.replaceSubrange(start..<endMarker, with: replacement)
        return result
    }

    private func injectingGUIUpdateBypass(into source: String) throws -> String {
        guard let start = source.range(of: "echo \"Checking for updates...\"")?.lowerBound,
              let end = source.range(of: "echo \"Checking for existing binaries...\"", range: start..<source.endIndex)?.lowerBound else {
            throw NSError(domain: "Surrealra1nGUI", code: 4, userInfo: [NSLocalizedDescriptionKey: "This surrealra1n version has an unsupported update-check layout."])
        }
        let replacement = "outdated=\"\"\necho \"Using the freshly downloaded surrealra1n engine.\"\n\n"
        var result = source
        result.replaceSubrange(start..<end, with: replacement)
        return result
    }

    private func injectingGUIBootSelection(into source: String) throws -> String {
        guard let function = source.range(of: "just_boot(){")?.upperBound,
              let bootDirectory = source.range(of: "\nbootdir=\"boot/$IDENTIFIER/$VERSION\"", range: function..<source.endIndex)?.lowerBound else {
            throw NSError(domain: "Surrealra1nGUI", code: 3, userInfo: [NSLocalizedDescriptionKey: "This surrealra1n version has an unsupported Just Boot layout."])
        }
        let replacement = """


if [[ -n "$SURREAL_GUI_BOOT_VERSION" ]]; then
    VERSION="$SURREAL_GUI_BOOT_VERSION"
elif [[ ! -f boot/$ECID.txt ]]; then
    read -p "Input the version you'd like to boot: " VERSION
else
    VERSION=$(cat boot/$ECID.txt)
fi
"""
        var result = source
        result.replaceSubrange(function..<bootDirectory, with: replacement)
        return result
    }

    private func cleanup() {
        if let url = temporaryScript { try? FileManager.default.removeItem(at: url) }
        if let url = environmentFile { try? FileManager.default.removeItem(at: url) }
        if let url = askpassFile { try? FileManager.default.removeItem(at: url) }
        temporaryScript = nil
        environmentFile = nil
        askpassFile = nil
        process = nil
    }
}
