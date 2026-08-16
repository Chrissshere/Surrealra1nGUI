import Cocoa

final class RestoreLogWindow: NSWindowController {
    private let textView = NSTextView()
    private var rawLog = ""
    private let renderer = TerminalOutput()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "surrealra1n Log"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func buildContent(in window: NSWindow) {
        guard let content = window.contentView else { return }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 46, width: 760, height: 414))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.documentView = textView

        textView.frame = scroll.contentView.bounds
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(calibratedWhite: 0.035, alpha: 1)
        textView.textColor = NSColor(calibratedRed: 0.76, green: 0.84, blue: 0.91, alpha: 1)
        textView.font = NSFont(name: "Menlo", size: 10.5) ?? .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        content.addSubview(scroll)

        let save = NSButton(title: "Save Log…", target: self, action: #selector(saveLog))
        save.font = InterfaceTheme.button
        save.frame = NSRect(x: 650, y: 9, width: 94, height: 29)
        save.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(save)
    }

    func present() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func clear() {
        rawLog = ""
        renderer.clear()
        textView.string = ""
    }

    func append(_ text: String) {
        rawLog += text
        textView.string = renderer.feed(text)
        textView.scrollToEndOfDocument(nil)
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

final class TerminalOutput {
    private enum EscapeState { case normal, escape, csi, osc, oscEscape }
    private var escapeState: EscapeState = .normal
    private var committed = ""
    private var line: [Character] = []
    private var cursor = 0
    private var csiParameters = ""
    private let visibleLimit = 500_000

    func clear() {
        escapeState = .normal
        committed = ""
        line = []
        cursor = 0
        csiParameters = ""
    }

    func feed(_ input: String) -> String {
        for character in input {
            if consumeEscape(character) { continue }
            switch character {
            case "\r":
                cursor = 0
            case "\n":
                committed += String(line) + "\n"
                line.removeAll(keepingCapacity: true)
                cursor = 0
                trimIfNeeded()
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
        return committed + String(line)
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
        guard committed.count > visibleLimit else { return }
        let start = committed.index(committed.endIndex, offsetBy: -visibleLimit)
        let suffix = String(committed[start...])
        if let newline = suffix.firstIndex(of: "\n") { committed = String(suffix[suffix.index(after: newline)...]) }
        else { committed = suffix }
    }
}
