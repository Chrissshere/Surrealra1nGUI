import Cocoa

final class RestoreLogWindow: NSWindowController {
    private let transcript = LogTranscriptView(background: NSColor(calibratedWhite: 0.035, alpha: 1))
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private var rawLog = ""
    private let renderer = TerminalOutput()
    private var displayRefreshPending = false
    private var automaticLogHandle: FileHandle?
    private(set) var automaticLogURL: URL?
    var onDisplayUpdate: ((String) -> Void)?
    var displayText: String { renderer.text }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "surrealra1n Log"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 340, height: 220)
        super.init(window: window)
        buildContent(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        try? automaticLogHandle?.close()
    }

    private func buildContent(in window: NSWindow) {
        guard let content = window.contentView else { return }

        let save = NSButton(title: "Save Log…", target: self, action: #selector(saveLog))
        save.font = InterfaceTheme.button
        revealButton.target = self
        revealButton.action = #selector(revealLog)
        revealButton.font = InterfaceTheme.button
        revealButton.isEnabled = false
        [transcript, save, revealButton].forEach { item in
            item.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(item)
        }
        NSLayoutConstraint.activate([
            transcript.topAnchor.constraint(equalTo: content.topAnchor),
            transcript.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            transcript.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -10),
            save.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            revealButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            revealButton.centerYAnchor.constraint(equalTo: save.centerYAnchor)
        ])
    }

    func present() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        transcript.showText(displayText)
    }

    func clear() {
        try? automaticLogHandle?.close()
        automaticLogHandle = nil
        automaticLogURL = nil
        revealButton.isEnabled = false
        rawLog = ""
        renderer.clear()
        transcript.showText("", reset: true)
        beginAutomaticLog()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        append("surrealra1n GUI \(version) (build \(build))\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nSession started: \(ISO8601DateFormatter().string(from: Date()))\n\n")
    }

    func append(_ text: String) {
        rawLog += text
        if let data = text.data(using: .utf8), let handle = automaticLogHandle {
            do {
                try handle.write(contentsOf: data)
            } catch {
                try? handle.close()
                automaticLogHandle = nil
            }
        }
        renderer.append(text)
        scheduleDisplayRefresh()
    }

    private func scheduleDisplayRefresh() {
        guard !displayRefreshPending else { return }
        displayRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
            guard let self else { return }
            self.displayRefreshPending = false
            let logVisible = self.window?.isVisible == true
            guard logVisible || self.onDisplayUpdate != nil else { return }
            let text = self.displayText
            if logVisible { self.transcript.showText(text) }
            self.onDisplayUpdate?(text)
        }
    }

    private func beginAutomaticLog() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Surrealra1nGUI", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let url = directory.appendingPathComponent("restore-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).log")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            automaticLogHandle = try FileHandle(forWritingTo: url)
            automaticLogURL = url
            revealButton.isEnabled = true
        } catch {
            automaticLogHandle = nil
            automaticLogURL = nil
        }
    }

    @objc private func revealLog() {
        guard let url = automaticLogURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func saveLog() {
        let panel = NSSavePanel()
        panel.title = "Save surrealra1n log"
        panel.nameFieldStringValue = "surrealra1n-\(Int(Date().timeIntervalSince1970)).log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try rawLog.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "surrealra1n"
            alert.informativeText = "The log could not be saved: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

final class LogTranscriptView: NSScrollView {
    private let textView = NSTextView()

    init(background: NSColor) {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = background

        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.backgroundColor = background
        textView.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        textView.font = InterfaceTheme.console
        textView.textContainerInset = NSSize(width: 10, height: 8)
        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showText(_ text: String, reset: Bool = false) {
        guard reset || textView.string != text else { return }
        let offset = contentView.bounds.origin
        let selection = textView.selectedRange()
        let followsTail = reset || (selection.length == 0 && textView.bounds.maxY <= documentVisibleRect.maxY + 20)
        textView.string = text
        if followsTail {
            textView.scrollToEndOfDocument(nil)
        } else {
            if selection.location != NSNotFound && NSMaxRange(selection) <= (text as NSString).length {
                textView.setSelectedRange(selection)
            }
            contentView.scroll(to: offset)
            reflectScrolledClipView(contentView)
        }
    }
}

final class TerminalOutput {
    private enum EscapeState { case normal, escape, csi, osc, oscEscape }
    private var escapeState: EscapeState = .normal
    private var committed = ""
    private var committedLength = 0
    private var line: [Character] = []
    private var cursor = 0
    private var csiParameters = ""
    private let visibleLimit = 160_000

    var text: String {
        let remaining = max(0, visibleLimit - line.count)
        let history = committedLength <= remaining ? committed : String(committed.suffix(remaining))
        return history + String(line.suffix(visibleLimit))
    }

    func clear() {
        escapeState = .normal
        committed = ""
        committedLength = 0
        line = []
        cursor = 0
        csiParameters = ""
    }

    func append(_ input: String) {
        for character in input {
            if consumeEscape(character) { continue }
            switch character {
            case "\r":
                cursor = 0
            case "\n", "\r\n":
                committed += String(line) + "\n"
                committedLength += line.count + 1
                line.removeAll(keepingCapacity: true)
                cursor = 0
            case "\u{0008}":
                if cursor > 0 {
                    cursor -= 1
                    if cursor < line.count { line.remove(at: cursor) }
                }
            default:
                guard !character.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) || character == "\t" else { continue }
                if cursor < line.count { line[cursor] = character }
                else { line.append(character) }
                cursor += 1
            }
        }
        trimIfNeeded()
    }

    private func consumeEscape(_ character: Character) -> Bool {
        switch escapeState {
        case .normal:
            if character == "\u{001B}" { escapeState = .escape; return true }
            return false
        case .escape:
            if character == "[" { csiParameters = ""; escapeState = .csi }
            else if character == "]" { escapeState = .osc }
            else { escapeState = .normal }
            return true
        case .csi:
            if let scalar = character.unicodeScalars.first, scalar.value >= 0x40 && scalar.value <= 0x7e {
                applyCSI(final: character)
                escapeState = .normal
            } else {
                csiParameters.append(character)
            }
            return true
        case .osc:
            if character == "\u{0007}" { escapeState = .normal }
            else if character == "\u{001B}" { escapeState = .oscEscape }
            return true
        case .oscEscape:
            escapeState = character == "\\" ? .normal : .osc
            return true
        }
    }

    private func applyCSI(final: Character) {
        guard final == "K" else { return }
        let mode = Int(csiParameters.split(separator: ";").first ?? "0") ?? 0
        switch mode {
        case 1:
            if !line.isEmpty {
                let end = min(cursor, line.count - 1)
                line.removeSubrange(0...end)
                cursor = 0
            }
        case 2:
            line.removeAll(keepingCapacity: true)
            cursor = 0
        default:
            if cursor < line.count { line.removeSubrange(cursor..<line.count) }
        }
    }

    private func trimIfNeeded() {
        guard committedLength > visibleLimit + 16_384 else { return }
        committed = String(committed.suffix(visibleLimit))
        committedLength = committed.count
    }
}
