import Cocoa
import UniformTypeIdentifiers

final class RestoreAssistantController: NSViewController, RestoreSessionDelegate {
    private enum Step {
        case welcome, options, operation, firmware, bootVersion, ready, handoff, dfuSequence, running, finished
    }

    private let restoreSession = RestoreSession()
    private let deviceObserver = DeviceObserver()
    private let engineWorkspace = EngineWorkspace()
    private var step: Step = .welcome
    private var operation: RestoreOperation = .tetheredRestore
    private var engineURL: URL?
    private var targetURL: URL?
    private var baseURL: URL?
    private var shshURL: URL?
    private var selectedBootVersion: String?
    private var bootVersions: [String] = []
    private var device: ConnectedDevice?
    private var currentPrompt: RestorePrompt?
    private var currentStage = "Preparing"
    private var currentProgress = 0.0
    private var currentOutputLine = "Waiting for surrealra1n output…"
    private var liveTranscript = ""
    private let inlineLogRenderer = TerminalOutput()
    private var finishedCode: Int32 = 0
    private var engineStatus = "Preparing surrealra1n…"
    private var engineDownloadFailed = false
    private var showLogsOnError = true
    private var demoMode = false
    private var demoIdentifier = "iPhone12,3"
    private var demoTimer: Timer?

    private var developerDemoEnabled: Bool {
        UserDefaults.standard.bool(forKey: "EnableDemoMode")
            || ProcessInfo.processInfo.arguments.contains("--enable-demo-mode")
    }

    private let demoDevices: [(String, String)] = [
        ("iPhone6,1", "iPhone 5s (iPhone6,1)"), ("iPhone6,2", "iPhone 5s (iPhone6,2)"),
        ("iPhone7,1", "iPhone 6 Plus (iPhone7,1)"), ("iPhone7,2", "iPhone 6 (iPhone7,2)"),
        ("iPhone8,1", "iPhone 6s (iPhone8,1)"), ("iPhone8,2", "iPhone 6s Plus (iPhone8,2)"),
        ("iPhone8,4", "iPhone SE (1st generation) (iPhone8,4)"),
        ("iPhone9,1", "iPhone 7 (iPhone9,1)"), ("iPhone9,2", "iPhone 7 Plus (iPhone9,2)"),
        ("iPhone9,3", "iPhone 7 (iPhone9,3)"), ("iPhone9,4", "iPhone 7 Plus (iPhone9,4)"),
        ("iPhone10,1", "iPhone 8 (iPhone10,1)"), ("iPhone10,2", "iPhone 8 Plus (iPhone10,2)"),
        ("iPhone10,3", "iPhone X (iPhone10,3)"), ("iPhone10,4", "iPhone 8 (iPhone10,4)"),
        ("iPhone10,5", "iPhone 8 Plus (iPhone10,5)"), ("iPhone10,6", "iPhone X (iPhone10,6)"),
        ("iPhone11,2", "iPhone XS (iPhone11,2)"), ("iPhone11,4", "iPhone XS Max (iPhone11,4)"),
        ("iPhone11,6", "iPhone XS Max (iPhone11,6)"), ("iPhone11,8", "iPhone XR (iPhone11,8)"),
        ("iPhone12,1", "iPhone 11 (iPhone12,1)"), ("iPhone12,3", "iPhone 11 Pro (iPhone12,3)"),
        ("iPhone12,5", "iPhone 11 Pro Max (iPhone12,5)"), ("iPhone12,8", "iPhone SE 2 (iPhone12,8)"),
        ("iPad4,1", "iPad Air (iPad4,1)"), ("iPad4,2", "iPad Air (iPad4,2)"),
        ("iPad4,3", "iPad Air (iPad4,3)"), ("iPad4,4", "iPad mini 2 (iPad4,4)"),
        ("iPad4,5", "iPad mini 2 (iPad4,5)"), ("iPad4,6", "iPad mini 2 (iPad4,6)"),
        ("iPad5,1", "iPad mini 4 (iPad5,1)"), ("iPad5,2", "iPad mini 4 (iPad5,2)"),
        ("iPad5,3", "iPad Air 2 (iPad5,3)"), ("iPad5,4", "iPad Air 2 (iPad5,4)"),
        ("iPad11,1", "iPad mini 5 (iPad11,1)"), ("iPad11,2", "iPad mini 5 (iPad11,2)"),
        ("iPad11,3", "iPad Air 3 (iPad11,3)"), ("iPad11,4", "iPad Air 3 (iPad11,4)"),
        ("iPod7,1", "iPod touch 6 (iPod7,1)")
    ]

    private let page = NSView()
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let auxiliaryButton = NSButton(title: "Options", target: nil, action: nil)
    private let nextButton = NSButton(title: "Start", target: nil, action: nil)
    private let logWindow = RestoreLogWindow()
    private weak var liveOutputLabel: NSTextField?
    private weak var liveConsoleView: NSTextView?
    private weak var promptTextField: NSTextField?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 326))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbRed: 48.0 / 255.0, green: 47.0 / 255.0, blue: 45.0 / 255.0, alpha: 1).cgColor
        buildFrame()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        restoreSession.delegate = self
        deviceObserver.onUpdate = { [weak self] device in
            guard let self = self else { return }
            guard !self.demoMode else { return }
            self.device = device
            if self.step == .welcome { self.render() }
        }
        deviceObserver.start()
        render()
        prepareEngine()
    }

    private func buildFrame() {
        page.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page)

        configureNavigationButton(backButton, action: #selector(goBack))
        configureNavigationButton(auxiliaryButton, action: #selector(auxiliaryAction))
        configureNavigationButton(nextButton, action: #selector(goNext), primary: true)
        view.addSubview(backButton)
        view.addSubview(auxiliaryButton)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: view.topAnchor, constant: 9),
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            page.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            page.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -49),

            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -9),
            auxiliaryButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -20),
            auxiliaryButton.bottomAnchor.constraint(equalTo: nextButton.bottomAnchor),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            nextButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -9)
        ])
    }

    private func configureNavigationButton(_ button: NSButton, action: Selector, primary: Bool = false) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = InterfaceTheme.button
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private func render() {
        liveOutputLabel = nil
        liveConsoleView = nil
        promptTextField = nil
        page.subviews.forEach { $0.removeFromSuperview() }
        switch step {
        case .welcome: renderWelcome()
        case .options: renderOptions()
        case .operation: renderOperation()
        case .firmware: renderFirmware()
        case .bootVersion: renderBootVersion()
        case .ready: renderReady()
        case .handoff: renderHandoff()
        case .dfuSequence: renderDFUSequence()
        case .running: renderRunning()
        case .finished: renderFinished()
        }
    }

    private func renderWelcome() {
        let title = heading("Welcome to surrealra1n!")
        let logo = LogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(title)
        page.addSubview(logo)

        let statusTitle: String
        let statusDetail: String
        if let device = device {
            statusTitle = "\(device.name) connected"
            let ecid = device.ecid.isEmpty ? "ECID unavailable" : "ECID \(device.ecid)"
            if !demoMode && !backendSupportsDevice {
                statusDetail = "\(device.identifier)  •  Unsupported by the current surrealra1n engine"
            } else {
                statusDetail = "\(device.identifier)  •  \(device.mode) mode  •  \(ecid)"
            }
        } else {
            statusTitle = "Connect an iPhone to begin."
            statusDetail = "Normal, Recovery, and DFU mode are detected automatically."
        }
        let status = label(statusTitle, size: 14, weight: .semibold)
        let visibleDetail = demoMode ? "\(device?.identifier ?? demoIdentifier)  •  Demo mode  •  No device commands will run" : statusDetail
        let detail = label(engineDownloadFailed && !demoMode ? "Could not download surrealra1n. Open Options to retry." : visibleDetail, size: 12, color: .secondaryLabelColor)
        let warning = label("NOTE: A tethered restore erases the device. Keep a backup and use this experimental software at your own risk.", size: 12.5, color: NSColor(srgbRed: 215.0 / 255.0, green: 213.0 / 255.0, blue: 214.0 / 255.0, alpha: 1), wrapping: true)
        warning.font = NSFontManager.shared.convert(warning.font!, toHaveTrait: .italicFontMask)
        let firstDivider = NSBox()
        firstDivider.boxType = .separator
        firstDivider.translatesAutoresizingMaskIntoConstraints = false
        let madeBy = label("GUI made by: chrissyx", size: 12.5, wrapping: true)
        let engineCredit = label("surrealra1n by: pwnerblu", size: 12.5, wrapping: true)
        let thanks = label("Thanks to: iSuns9, bodyc1m, Mineek, Remedgit, BatuBey5G, the checkra1n team, and the usbliter8 developers", size: 12.5, wrapping: true)
        let heart = label("With 💖 from chrissyx", size: 13)
        let secondDivider = NSBox()
        secondDivider.boxType = .separator
        secondDivider.translatesAutoresizingMaskIntoConstraints = false
        [status, detail, firstDivider, madeBy, engineCredit, thanks, heart, secondDivider, warning].forEach(page.addSubview)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: page.leadingAnchor), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 2),
            logo.trailingAnchor.constraint(equalTo: page.trailingAnchor), logo.topAnchor.constraint(equalTo: page.topAnchor),
            logo.widthAnchor.constraint(equalToConstant: 64), logo.heightAnchor.constraint(equalToConstant: 64),
            status.leadingAnchor.constraint(equalTo: page.leadingAnchor), status.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            status.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -80),
            detail.leadingAnchor.constraint(equalTo: status.leadingAnchor), detail.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8),
            detail.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            firstDivider.leadingAnchor.constraint(equalTo: page.leadingAnchor), firstDivider.trailingAnchor.constraint(equalTo: page.trailingAnchor), firstDivider.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 24),
            madeBy.leadingAnchor.constraint(equalTo: page.leadingAnchor), madeBy.trailingAnchor.constraint(equalTo: page.trailingAnchor), madeBy.topAnchor.constraint(equalTo: firstDivider.bottomAnchor, constant: 10),
            engineCredit.leadingAnchor.constraint(equalTo: page.leadingAnchor), engineCredit.topAnchor.constraint(equalTo: madeBy.bottomAnchor, constant: 3),
            thanks.leadingAnchor.constraint(equalTo: page.leadingAnchor), thanks.trailingAnchor.constraint(equalTo: page.trailingAnchor), thanks.topAnchor.constraint(equalTo: engineCredit.bottomAnchor, constant: 12),
            heart.leadingAnchor.constraint(equalTo: page.leadingAnchor), heart.topAnchor.constraint(equalTo: thanks.bottomAnchor, constant: 12),
            secondDivider.leadingAnchor.constraint(equalTo: page.leadingAnchor), secondDivider.trailingAnchor.constraint(equalTo: page.trailingAnchor), secondDivider.topAnchor.constraint(equalTo: heart.bottomAnchor, constant: 12),
            warning.leadingAnchor.constraint(equalTo: page.leadingAnchor), warning.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            warning.topAnchor.constraint(equalTo: secondDivider.bottomAnchor, constant: 10)
        ])

        backButton.isHidden = true
        auxiliaryButton.isHidden = false
        auxiliaryButton.title = "Options"
        nextButton.isHidden = false
        nextButton.title = engineURL == nil && !engineDownloadFailed && !demoMode ? "Loading…" : "Start"
        nextButton.isEnabled = device != nil && (engineURL != nil || demoMode) && (demoMode || backendSupportsDevice)
    }

    private func renderOptions() {
        let title = heading("Options")
        let intro = label("surrealra1n is prepared automatically. No local engine folder is used.", size: 13, wrapping: true)
        let automatic = NSButton(checkboxWithTitle: "Open the complete log when an error occurs", target: self, action: #selector(toggleErrorLogs))
        automatic.state = showLogsOnError ? .on : .off
        automatic.controlSize = .regular
        automatic.font = InterfaceTheme.body
        automatic.translatesAutoresizingMaskIntoConstraints = false
        let demo = NSButton(checkboxWithTitle: "UI Demo Mode (fake device and restore)", target: self, action: #selector(toggleDemoMode))
        demo.state = demoMode ? .on : .off
        demo.controlSize = .regular
        demo.font = InterfaceTheme.body
        demo.translatesAutoresizingMaskIntoConstraints = false
        let demoDeviceTitle = label("Fake device", size: 12, color: InterfaceTheme.muted)
        let demoDevice = NSPopUpButton()
        demoDevice.addItems(withTitles: demoDevices.map { $0.1 })
        if let index = demoDevices.firstIndex(where: { $0.0 == demoIdentifier }) { demoDevice.selectItem(at: index) }
        demoDevice.target = self
        demoDevice.action = #selector(selectDemoDevice(_:))
        demoDevice.font = InterfaceTheme.button
        demoDevice.isEnabled = demoMode
        demoDevice.translatesAutoresizingMaskIntoConstraints = false
        let bootchainsTitle = label("Bootchain library", size: 12, weight: .semibold)
        let bootchainsPath = label(displayPath(engineWorkspace.bootchainsDirectory), size: 11, color: InterfaceTheme.muted)
        bootchainsPath.lineBreakMode = .byTruncatingMiddle
        let chooseBootchains = actionButton("Change…", action: #selector(chooseBootchainsDirectory))
        let resetBootchains = actionButton("Default", action: #selector(resetBootchainsDirectory))
        let repository = label("Source: github.com/pwnerblu/surrealra1n (development)", size: 12, color: .secondaryLabelColor, wrapping: true)
        let state = label(engineStatus, size: 12, color: engineDownloadFailed ? .systemRed : .secondaryLabelColor, wrapping: true)
        let retry = actionButton("Download Again", action: #selector(retryEngineDownload))
        retry.isHidden = !engineDownloadFailed
        [title, intro, automatic, bootchainsTitle, bootchainsPath, chooseBootchains, resetBootchains, repository, state, retry].forEach(page.addSubview)
        if developerDemoEnabled { [demo, demoDeviceTitle, demoDevice].forEach(page.addSubview) }
        var constraints = [
            title.leadingAnchor.constraint(equalTo: page.leadingAnchor), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
            intro.leadingAnchor.constraint(equalTo: page.leadingAnchor), intro.trailingAnchor.constraint(equalTo: page.trailingAnchor), intro.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            automatic.leadingAnchor.constraint(equalTo: page.leadingAnchor), automatic.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 22),
            bootchainsTitle.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            bootchainsPath.leadingAnchor.constraint(equalTo: page.leadingAnchor), bootchainsPath.centerYAnchor.constraint(equalTo: chooseBootchains.centerYAnchor),
            chooseBootchains.leadingAnchor.constraint(equalTo: bootchainsPath.trailingAnchor, constant: 8), chooseBootchains.widthAnchor.constraint(equalToConstant: 72),
            resetBootchains.leadingAnchor.constraint(equalTo: chooseBootchains.trailingAnchor, constant: 6), resetBootchains.trailingAnchor.constraint(equalTo: page.trailingAnchor), resetBootchains.centerYAnchor.constraint(equalTo: chooseBootchains.centerYAnchor), resetBootchains.widthAnchor.constraint(equalToConstant: 64),
            repository.leadingAnchor.constraint(equalTo: page.leadingAnchor), repository.trailingAnchor.constraint(equalTo: page.trailingAnchor), repository.topAnchor.constraint(equalTo: chooseBootchains.bottomAnchor, constant: 8),
            state.leadingAnchor.constraint(equalTo: page.leadingAnchor), state.trailingAnchor.constraint(equalTo: page.trailingAnchor), state.topAnchor.constraint(equalTo: repository.bottomAnchor, constant: 10),
            retry.leadingAnchor.constraint(equalTo: page.leadingAnchor), retry.topAnchor.constraint(equalTo: state.bottomAnchor, constant: 12)
        ]
        if developerDemoEnabled {
            constraints += [
                demo.leadingAnchor.constraint(equalTo: page.leadingAnchor), demo.topAnchor.constraint(equalTo: automatic.bottomAnchor, constant: 8),
                demoDeviceTitle.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 20), demoDeviceTitle.centerYAnchor.constraint(equalTo: demoDevice.centerYAnchor),
                demoDevice.leadingAnchor.constraint(equalTo: demoDeviceTitle.trailingAnchor, constant: 12), demoDevice.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor), demoDevice.topAnchor.constraint(equalTo: demo.bottomAnchor, constant: 5), demoDevice.widthAnchor.constraint(equalToConstant: 245),
                bootchainsTitle.topAnchor.constraint(equalTo: demoDevice.bottomAnchor, constant: 8)
            ]
        } else {
            constraints.append(bootchainsTitle.topAnchor.constraint(equalTo: automatic.bottomAnchor, constant: 16))
        }
        constraints += [
            bootchainsPath.topAnchor.constraint(equalTo: bootchainsTitle.bottomAnchor, constant: 4),
            chooseBootchains.centerYAnchor.constraint(equalTo: bootchainsPath.centerYAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        backButton.isHidden = false
        auxiliaryButton.isHidden = true
        nextButton.isHidden = true
    }

    private func renderOperation() {
        let title = heading("What would you like to do?")
        let available = demoMode || backendSupportsDevice
        if operation == .restoreWithBlobs && !supportsBlobRestore {
            operation = .tetheredRestore
        }
        let introText = available
            ? "These are the four downgrade functions exposed by this device's surrealra1n menu."
            : "This model has a GUI profile, but the current surrealra1n development engine rejects it before the restore menu."
        let intro = label(introText, size: 12, color: available ? nil : .systemOrange, wrapping: true)
        let blobs = radioButton("Restore with SHSH blobs", selected: operation == .restoreWithBlobs, action: #selector(selectBlobRestore))
        blobs.isEnabled = available && supportsBlobRestore
        let blobsDetail = label(supportsBlobRestore ? "Use a previously saved SHSH2 ticket." : "Unavailable for A12 and A13 devices.", size: 11, color: InterfaceTheme.muted)
        let restore = radioButton("Restore tethered", selected: operation == .tetheredRestore, action: #selector(selectRestore))
        restore.isEnabled = available
        let restoreDetail = label("Restore with the latest signed firmware as the base.", size: 11, color: InterfaceTheme.muted)
        let ota = radioButton("Restore 10.3.3 untethered", selected: operation == .untethered1033, action: #selector(select1033Restore))
        ota.isEnabled = available && supports1033Restore
        let otaDetail = label(supports1033Restore ? "Available for this A7 device." : "Only available for supported A7 devices.", size: 11, color: InterfaceTheme.muted)
        let boot = radioButton("Just Boot", selected: operation == .justBoot, action: #selector(selectBoot))
        boot.isEnabled = available
        let bootDetail = label("Boot an already-restored tethered system.", size: 11, color: InterfaceTheme.muted)
        [title, intro, blobs, blobsDetail, restore, restoreDetail, ota, otaDetail, boot, bootDetail].forEach(page.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: page.leadingAnchor), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
            intro.leadingAnchor.constraint(equalTo: page.leadingAnchor), intro.trailingAnchor.constraint(equalTo: page.trailingAnchor), intro.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            blobs.leadingAnchor.constraint(equalTo: page.leadingAnchor), blobs.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12),
            blobsDetail.leadingAnchor.constraint(equalTo: blobs.leadingAnchor, constant: 20), blobsDetail.topAnchor.constraint(equalTo: blobs.bottomAnchor),
            restore.leadingAnchor.constraint(equalTo: page.leadingAnchor), restore.topAnchor.constraint(equalTo: blobsDetail.bottomAnchor, constant: 8),
            restoreDetail.leadingAnchor.constraint(equalTo: restore.leadingAnchor, constant: 20), restoreDetail.topAnchor.constraint(equalTo: restore.bottomAnchor),
            ota.leadingAnchor.constraint(equalTo: page.leadingAnchor), ota.topAnchor.constraint(equalTo: restoreDetail.bottomAnchor, constant: 8),
            otaDetail.leadingAnchor.constraint(equalTo: ota.leadingAnchor, constant: 20), otaDetail.topAnchor.constraint(equalTo: ota.bottomAnchor),
            boot.leadingAnchor.constraint(equalTo: page.leadingAnchor), boot.topAnchor.constraint(equalTo: otaDetail.bottomAnchor, constant: 8),
            bootDetail.leadingAnchor.constraint(equalTo: boot.leadingAnchor, constant: 20), bootDetail.topAnchor.constraint(equalTo: boot.bottomAnchor, constant: 3)
        ])
        standardNavigation(next: "Continue")
        nextButton.isEnabled = available
            && (operation != .untethered1033 || supports1033Restore)
            && (operation != .restoreWithBlobs || supportsBlobRestore)
    }

    private func renderFirmware() {
        let title = heading("Choose restore firmware")
        let introText: String
        switch operation {
        case .restoreWithBlobs: introText = "Select the target IPSW and its matching SHSH2 ticket."
        case .untethered1033: introText = "Select the iOS 10.3.3 IPSW used by the A7 OTA restore path."
        default: introText = "Select the target version and currently signed base IPSW required by surrealra1n."
        }
        let intro = label(introText, size: 13, wrapping: true)
        let targetTitle = label("Target IPSW", size: 13, weight: .semibold)
        let targetName = label(targetURL?.lastPathComponent ?? "No target selected", size: 12, color: .secondaryLabelColor)
        let targetChoose = actionButton("Choose…", action: #selector(selectTarget))
        [title, intro, targetTitle, targetName, targetChoose].forEach(page.addSubview)
        var constraints = [
            title.leadingAnchor.constraint(equalTo: page.leadingAnchor), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
            intro.leadingAnchor.constraint(equalTo: page.leadingAnchor), intro.trailingAnchor.constraint(equalTo: page.trailingAnchor), intro.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            targetTitle.leadingAnchor.constraint(equalTo: page.leadingAnchor), targetTitle.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 30),
            targetChoose.trailingAnchor.constraint(equalTo: page.trailingAnchor), targetChoose.centerYAnchor.constraint(equalTo: targetTitle.centerYAnchor),
            targetChoose.widthAnchor.constraint(equalToConstant: 82),
            targetName.leadingAnchor.constraint(equalTo: page.leadingAnchor), targetName.trailingAnchor.constraint(equalTo: targetChoose.leadingAnchor, constant: -14), targetName.topAnchor.constraint(equalTo: targetTitle.bottomAnchor, constant: 7)
        ]

        if operation != .untethered1033 {
            let secondTitleText = operation == .restoreWithBlobs ? "SHSH2 ticket" : "Signed base IPSW"
            let secondNameText = operation == .restoreWithBlobs ? (shshURL?.lastPathComponent ?? "No SHSH2 selected") : (baseURL?.lastPathComponent ?? "No base selected")
            let secondTitle = label(secondTitleText, size: 13, weight: .semibold)
            let secondName = label(secondNameText, size: 12, color: .secondaryLabelColor)
            let secondChoose = actionButton("Choose…", action: operation == .restoreWithBlobs ? #selector(selectSHSH) : #selector(selectBase))
            [secondTitle, secondName, secondChoose].forEach(page.addSubview)
            constraints += [
                secondTitle.leadingAnchor.constraint(equalTo: page.leadingAnchor), secondTitle.topAnchor.constraint(equalTo: targetName.bottomAnchor, constant: 32),
                secondChoose.trailingAnchor.constraint(equalTo: page.trailingAnchor), secondChoose.centerYAnchor.constraint(equalTo: secondTitle.centerYAnchor), secondChoose.widthAnchor.constraint(equalToConstant: 82),
                secondName.leadingAnchor.constraint(equalTo: page.leadingAnchor), secondName.trailingAnchor.constraint(equalTo: secondChoose.leadingAnchor, constant: -14), secondName.topAnchor.constraint(equalTo: secondTitle.bottomAnchor, constant: 7)
            ]
        }
        NSLayoutConstraint.activate(constraints)
        standardNavigation(next: "Continue")
        switch operation {
        case .restoreWithBlobs: nextButton.isEnabled = targetURL != nil && shshURL != nil
        case .untethered1033: nextButton.isEnabled = targetURL != nil
        default: nextButton.isEnabled = targetURL != nil && baseURL != nil
        }
    }

    private func renderBootVersion() {
        refreshBootVersions()
        let title = heading("Choose a system to boot")
        let intro = label("Just Boot uses files generated for this exact device. You can also import an existing bootchain folder.", size: 13, wrapping: true)
        let versionTitle = label("Installed tethered iOS version", size: 13, weight: .semibold)
        let popup = NSPopUpButton()
        popup.addItems(withTitles: bootVersions)
        if let selected = selectedBootVersion, let index = bootVersions.firstIndex(of: selected) { popup.selectItem(at: index) }
        popup.target = self
        popup.action = #selector(selectBootVersion(_:))
        popup.font = InterfaceTheme.button
        popup.isEnabled = !bootVersions.isEmpty
        popup.translatesAutoresizingMaskIntoConstraints = false
        let importButton = actionButton("Import Bootchain…", action: #selector(importBootchains))
        let explanation = label(bootVersions.isEmpty
            ? "No complete boot set was found. Import one, or complete a tethered restore with this GUI."
            : "The newest generated version is selected automatically. Choose another version here if needed.",
            size: 12, color: bootVersions.isEmpty ? .systemOrange : InterfaceTheme.muted, wrapping: true)
        [title, intro, versionTitle, popup, importButton, explanation].forEach(page.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: page.leadingAnchor), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
            intro.leadingAnchor.constraint(equalTo: page.leadingAnchor), intro.trailingAnchor.constraint(equalTo: page.trailingAnchor), intro.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            versionTitle.leadingAnchor.constraint(equalTo: page.leadingAnchor), versionTitle.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 32),
            popup.leadingAnchor.constraint(equalTo: page.leadingAnchor), popup.topAnchor.constraint(equalTo: versionTitle.bottomAnchor, constant: 10), popup.widthAnchor.constraint(equalToConstant: 210),
            importButton.leadingAnchor.constraint(equalTo: popup.trailingAnchor, constant: 12), importButton.centerYAnchor.constraint(equalTo: popup.centerYAnchor), importButton.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor),
            explanation.leadingAnchor.constraint(equalTo: page.leadingAnchor), explanation.trailingAnchor.constraint(equalTo: page.trailingAnchor), explanation.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 22)
        ])
        standardNavigation(next: "Continue")
        nextButton.isEnabled = selectedBootVersion != nil
    }

    private func renderReady() {
        let destructive = operation != .justBoot
        let title = heading(destructive ? "Ready to restore" : "Ready to boot")
        let deviceText = device.map { "\($0.name) (\($0.identifier))\n\($0.mode) mode • ECID \($0.ecid)" } ?? "No device detected"
        let summary = label(deviceText, size: 15, weight: .semibold, wrapping: true)
        let details: String
        if operation == .restoreWithBlobs {
            details = "Target: \(targetURL?.lastPathComponent ?? "Not selected")\nSHSH2: \(shshURL?.lastPathComponent ?? "Not selected")"
        } else if operation == .tetheredRestore {
            details = "Target: \(targetURL?.lastPathComponent ?? "Not selected")\nBase: \(baseURL?.lastPathComponent ?? "Not selected")"
        } else if operation == .untethered1033 {
            details = "Target: \(targetURL?.lastPathComponent ?? "Not selected")\nA7 OTA restore path"
        } else {
            details = "Boot version: \(selectedBootVersion ?? "Not selected")\nsurrealra1n will use the generated boot files for this device."
        }
        let files = label(details, size: 13, color: .secondaryLabelColor, wrapping: true)
        let warning = label(destructive ? "This operation erases the device. Do not unplug it after the restore begins." : "Keep the device connected until the boot finishes.", size: 13, color: NSColor.systemOrange, wrapping: true)
        [title, summary, files, warning].forEach(page.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: page.leadingAnchor), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
            summary.leadingAnchor.constraint(equalTo: page.leadingAnchor), summary.trailingAnchor.constraint(equalTo: page.trailingAnchor), summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 30),
            files.leadingAnchor.constraint(equalTo: page.leadingAnchor), files.trailingAnchor.constraint(equalTo: page.trailingAnchor), files.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 26),
            warning.leadingAnchor.constraint(equalTo: page.leadingAnchor), warning.trailingAnchor.constraint(equalTo: page.trailingAnchor), warning.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -12)
        ])
        standardNavigation(next: destructive ? "Start Restore" : "Start Boot")
    }

    private func renderHandoff() {
        let phone = phoneArtwork(named: dfuProfile.assetName)
        let title = heading(handoffTitle)
        let instructions = label(handoffInstructions, size: 14, color: NSColor(calibratedWhite: 0.86, alpha: 1), wrapping: true)
        page.addSubview(phone)
        page.addSubview(title)
        page.addSubview(instructions)
        var fieldConstraints: [NSLayoutConstraint] = []
        if case .textInput = currentPrompt {
            let field = NSTextField()
            field.placeholderString = "Installed iOS version, for example 15.6.1"
            field.font = InterfaceTheme.body
            field.translatesAutoresizingMaskIntoConstraints = false
            page.addSubview(field)
            promptTextField = field
            fieldConstraints = [
                field.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: page.trailingAnchor),
                field.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 18),
                field.heightAnchor.constraint(equalToConstant: 24)
            ]
            DispatchQueue.main.async { [weak field] in field?.window?.makeFirstResponder(field) }
        }
        NSLayoutConstraint.activate([
            phone.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 34), phone.centerYAnchor.constraint(equalTo: page.centerYAnchor),
            phone.widthAnchor.constraint(equalToConstant: 118), phone.heightAnchor.constraint(equalToConstant: 220),
            title.leadingAnchor.constraint(equalTo: phone.trailingAnchor, constant: 48), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 42),
            title.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            instructions.leadingAnchor.constraint(equalTo: title.leadingAnchor), instructions.trailingAnchor.constraint(equalTo: page.trailingAnchor), instructions.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24)
        ] + fieldConstraints)
        backButton.isHidden = true
        auxiliaryButton.isHidden = false
        auxiliaryButton.title = promptHasNegativeChoice ? "No / Reuse" : "Show Logs"
        nextButton.isHidden = false
        nextButton.title = handoffButtonTitle
        nextButton.isEnabled = true
    }

    private func renderRunning() {
        let title = heading(operation == .justBoot ? "Booting device…" : "Restoring device…")
        let stage = label(currentStage, size: 13, weight: .semibold, wrapping: true)
        let percent = label("\(Int((currentProgress * 100).rounded()))%", size: 12, weight: .semibold)
        percent.font = InterfaceTheme.percentage
        percent.alignment = .right
        let progress = NSProgressIndicator()
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = currentProgress
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.controlSize = .small
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(calibratedWhite: 0.105, alpha: 1)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let console = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 132))
        console.isEditable = false
        console.isSelectable = true
        console.isRichText = false
        console.isVerticallyResizable = true
        console.isHorizontallyResizable = false
        console.autoresizingMask = [.width]
        console.minSize = NSSize(width: 0, height: 132)
        console.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        console.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        console.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        console.backgroundColor = scroll.backgroundColor
        console.textContainerInset = NSSize(width: 7, height: 6)
        console.string = liveTranscript
        scroll.documentView = console
        liveConsoleView = console
        [title, stage, percent, progress, scroll].forEach(page.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 12), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 5),
            stage.leadingAnchor.constraint(equalTo: title.leadingAnchor), stage.trailingAnchor.constraint(equalTo: percent.leadingAnchor, constant: -12), stage.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            percent.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24), percent.firstBaselineAnchor.constraint(equalTo: stage.firstBaselineAnchor), percent.widthAnchor.constraint(equalToConstant: 42),
            progress.leadingAnchor.constraint(equalTo: title.leadingAnchor), progress.trailingAnchor.constraint(equalTo: percent.trailingAnchor), progress.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: percent.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 9), scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -2)
        ])
        console.scrollToEndOfDocument(nil)
        backButton.isHidden = true
        auxiliaryButton.isHidden = false
        auxiliaryButton.title = "Show Logs"
        nextButton.isHidden = false
        nextButton.title = "Cancel"
        nextButton.isEnabled = true
    }

    private func renderDFUSequence() {
        let profile = dfuProfile
        let phone = phoneArtwork(named: profile.assetName)
        let intro = label("Time to put the device into DFU mode. Locate the buttons as marked below on your device and check the instructions on the right before continuing.", size: 12, wrapping: true)
        let readyActive = currentStage.localizedCaseInsensitiveContains("get ready")
        let bothActive = profile.secondStageTerms.contains { currentStage.localizedCaseInsensitiveContains($0) }
        let releaseActive = profile.thirdStageTerms.contains { currentStage.localizedCaseInsensitiveContains($0) }
        let leftAction = bothActive ? "HOLD" : (releaseActive ? "KEEP HOLDING" : "")
        let rightAction = bothActive ? "HOLD" : (releaseActive ? "RELEASE" : "")
        let leftCallout = label(leftAction.isEmpty ? profile.leftCallout : "\(leftAction)\n\(profile.leftCallout)", size: 11, weight: leftAction.isEmpty ? .regular : .semibold, color: leftAction.isEmpty ? InterfaceTheme.muted : InterfaceTheme.foreground, wrapping: true)
        leftCallout.alignment = .right
        leftCallout.maximumNumberOfLines = 2
        let rightCallout = label(rightAction.isEmpty ? profile.rightCallout : "\(profile.rightCallout)\n\(rightAction)", size: 11, weight: rightAction.isEmpty ? .regular : .semibold, color: rightAction.isEmpty ? InterfaceTheme.muted : InterfaceTheme.foreground, wrapping: true)
        rightCallout.maximumNumberOfLines = 2
        leftCallout.isHidden = !bothActive && !releaseActive
        rightCallout.isHidden = !bothActive
        let actionSummary: String
        if readyActive {
            actionSummary = "Get ready. Do not press any buttons yet."
        } else if bothActive {
            actionSummary = profile.secondInstruction
        } else if releaseActive {
            actionSummary = profile.thirdInstruction
        } else {
            actionSummary = "Follow the highlighted step."
        }
        let action = label(actionSummary, size: 11, weight: .semibold, color: InterfaceTheme.foreground, wrapping: true)
        let ready = dfuLine("1.  Get ready\(readyActive ? dfuCountdown : "")", active: readyActive)
        let both = dfuLine("2.  \(profile.secondInstruction)\(bothActive ? dfuCountdown : "")", active: bothActive)
        let release = dfuLine("3.  \(profile.thirdInstruction)\(releaseActive ? dfuCountdown : "")", active: releaseActive)
        [phone, intro, leftCallout, rightCallout, ready, both, release, action].forEach(page.addSubview)
        NSLayoutConstraint.activate([
            intro.leadingAnchor.constraint(equalTo: page.leadingAnchor), intro.trailingAnchor.constraint(equalTo: page.trailingAnchor), intro.topAnchor.constraint(equalTo: page.topAnchor, constant: 1),
            phone.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: profile.imageLeading), phone.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 10),
            phone.widthAnchor.constraint(equalToConstant: profile.imageWidth), phone.heightAnchor.constraint(equalToConstant: 190),
            leftCallout.leadingAnchor.constraint(greaterThanOrEqualTo: page.leadingAnchor), leftCallout.trailingAnchor.constraint(equalTo: phone.leadingAnchor, constant: 6),
            rightCallout.leadingAnchor.constraint(equalTo: phone.trailingAnchor, constant: -6), rightCallout.trailingAnchor.constraint(lessThanOrEqualTo: ready.leadingAnchor, constant: -8),
            calloutConstraint(leftCallout, relativeTo: phone, position: profile.leftPosition),
            calloutConstraint(rightCallout, relativeTo: phone, position: profile.rightPosition),
            ready.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 292), ready.trailingAnchor.constraint(equalTo: page.trailingAnchor), ready.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 16),
            both.leadingAnchor.constraint(equalTo: ready.leadingAnchor), both.trailingAnchor.constraint(equalTo: page.trailingAnchor), both.topAnchor.constraint(equalTo: ready.bottomAnchor, constant: 13),
            release.leadingAnchor.constraint(equalTo: ready.leadingAnchor), release.trailingAnchor.constraint(equalTo: page.trailingAnchor), release.topAnchor.constraint(equalTo: both.bottomAnchor, constant: 13),
            action.leadingAnchor.constraint(equalTo: ready.leadingAnchor), action.trailingAnchor.constraint(equalTo: page.trailingAnchor), action.topAnchor.constraint(equalTo: release.bottomAnchor, constant: 14)
        ])
        backButton.isHidden = true
        auxiliaryButton.isHidden = false
        auxiliaryButton.title = "Show Logs"
        nextButton.isHidden = false
        nextButton.title = "Cancel"
        nextButton.isEnabled = true
    }

    private func dfuLine(_ text: String, active: Bool) -> NSTextField {
        label(text, size: 12, weight: active ? .semibold : .regular, color: active ? InterfaceTheme.foreground : NSColor(calibratedWhite: 0.40, alpha: 1), wrapping: true)
    }

    private var dfuCountdown: String {
        guard let range = currentStage.range(of: #"\s*\([0-9]+\)"#, options: .regularExpression) else { return "" }
        return String(currentStage[range])
    }

    private func renderFinished() {
        let success = finishedCode == 0
        let title = heading(success ? "All done" : "The operation stopped")
        let symbol = label(success ? "✓" : "!", size: 62, weight: .bold, color: success ? .systemGreen : .systemRed)
        symbol.alignment = .center
        let message = label(success ? "surrealra1n finished successfully." : "surrealra1n exited with code \(finishedCode). Open the log for the exact failure.", size: 15, wrapping: true)
        message.alignment = .center
        [title, symbol, message].forEach(page.addSubview)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: page.centerXAnchor), title.topAnchor.constraint(equalTo: page.topAnchor, constant: 44),
            symbol.centerXAnchor.constraint(equalTo: page.centerXAnchor), symbol.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 28),
            message.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 60), message.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -60), message.topAnchor.constraint(equalTo: symbol.bottomAnchor, constant: 20)
        ])
        backButton.isHidden = true
        auxiliaryButton.isHidden = false
        auxiliaryButton.title = "Show Logs"
        nextButton.isHidden = false
        nextButton.title = "Done"
        nextButton.isEnabled = true
    }

    private func standardNavigation(next title: String) {
        backButton.isHidden = false
        auxiliaryButton.isHidden = true
        nextButton.isHidden = false
        nextButton.title = title
        nextButton.isEnabled = true
    }

    @objc private func goBack() {
        switch step {
        case .options: step = .welcome
        case .operation: step = .welcome
        case .firmware: step = .operation
        case .bootVersion: step = .operation
        case .ready: step = operation == .justBoot ? .bootVersion : .firmware
        default: return
        }
        render()
    }

    @objc private func goNext() {
        switch step {
        case .welcome:
            step = .operation
        case .operation:
            if operation == .justBoot {
                selectedBootVersion = nil
                bootVersions = []
                step = .bootVersion
            } else {
                step = .firmware
            }
        case .firmware:
            step = .ready
        case .bootVersion:
            guard selectedBootVersion != nil else { return }
            step = .ready
        case .ready:
            beginOperation()
            return
        case .handoff:
            answerPrompt(positive: true)
            return
        case .running, .dfuSequence:
            confirmCancel()
            return
        case .finished:
            currentProgress = 0
            currentStage = "Preparing"
            step = .welcome
        case .options:
            return
        }
        render()
    }

    @objc private func auxiliaryAction() {
        switch step {
        case .welcome:
            step = .options
            render()
        case .handoff:
            if promptHasNegativeChoice { answerPrompt(positive: false) } else { showLogs() }
        case .running, .dfuSequence, .finished:
            showLogs()
        default:
            break
        }
    }

    @objc private func selectBlobRestore() {
        guard supportsBlobRestore else { return }
        operation = .restoreWithBlobs
        render()
    }
    @objc private func selectRestore() { operation = .tetheredRestore; render() }
    @objc private func select1033Restore() { if supports1033Restore { operation = .untethered1033; render() } }
    @objc private func selectBoot() { operation = .justBoot; selectedBootVersion = nil; bootVersions = []; render() }

    @objc private func selectBootVersion(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        selectedBootVersion = bootVersions[sender.indexOfSelectedItem]
        render()
    }

    @objc private func importBootchains() {
        guard let identifier = device?.identifier else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Bootchains for \(identifier)"
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selected = panel.url else { return }

        guard completeBootSet(at: selected, identifier: identifier) else {
            let alert = NSAlert()
            alert.messageText = "No complete bootchain was found"
            alert.informativeText = "Choose one version folder containing the complete boot files required by \(identifier)."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        guard let version = importedBootchainVersion(for: selected) else { return }

        do {
            try engineWorkspace.importBootchainVersion(from: selected, identifier: identifier, version: version)
            selectedBootVersion = version
            refreshBootVersions()
            render()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not import the bootchains"
            alert.runModal()
        }
    }

    private func importedBootchainVersion(for folder: URL) -> String? {
        let proposed = folder.lastPathComponent
        let versionPattern = #"^[0-9]+(?:\.[0-9]+){1,2}$"#
        if proposed.range(of: versionPattern, options: .regularExpression) != nil { return proposed }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "For example 16.4"
        let alert = NSAlert()
        alert.messageText = "Name this bootchain version"
        alert.informativeText = "The selected folder is not named like an iOS version. Enter the exact installed version this bootchain boots."
        alert.accessoryView = field
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let version = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.range(of: versionPattern, options: .regularExpression) != nil else {
            let invalid = NSAlert()
            invalid.messageText = "Invalid iOS version"
            invalid.informativeText = "Use a numeric version such as 16.4 or 15.6.1."
            invalid.alertStyle = .warning
            invalid.runModal()
            return nil
        }
        return version
    }

    private var supports1033Restore: Bool {
        guard let identifier = device?.identifier else { return false }
        return identifier.hasPrefix("iPhone6,") || ["iPad4,1", "iPad4,2", "iPad4,3", "iPad4,4", "iPad4,5"].contains(identifier)
    }

    private var supportsBlobRestore: Bool {
        guard let identifier = device?.identifier else { return false }
        return !identifier.hasPrefix("iPhone11,")
            && !identifier.hasPrefix("iPhone12,")
            && !identifier.hasPrefix("iPad11,")
    }

    private var backendSupportsDevice: Bool {
        guard let identifier = device?.identifier else { return false }
        let exact = [
            "iPhone6,1", "iPhone6,2", "iPhone7,1", "iPhone7,2",
            "iPhone10,1", "iPhone10,2", "iPhone10,3", "iPhone10,4", "iPhone10,5", "iPhone10,6",
            "iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8",
            "iPhone12,1", "iPhone12,3", "iPhone12,5", "iPhone12,8",
            "iPad4,1", "iPad4,2", "iPad4,3", "iPad4,4", "iPad4,5", "iPad4,6",
            "iPad5,1", "iPad5,2", "iPad5,3", "iPad5,4",
            "iPad11,1", "iPad11,2", "iPad11,3", "iPad11,4", "iPod7,1"
        ]
        return exact.contains(identifier)
    }

    private func refreshBootVersions() {
        let identifier = device?.identifier ?? demoIdentifier
        let versions: [String]
        if demoMode {
            versions = ["16.4", "15.6.1", "14.8"]
        } else if let engine = engineURL {
            let root = engine.appendingPathComponent("boot", isDirectory: true).appendingPathComponent(identifier, isDirectory: true)
            let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            versions = urls.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && completeBootSet(at: url, identifier: identifier)
            }.map(\.lastPathComponent)
        } else {
            versions = []
        }
        bootVersions = Array(Set(versions)).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        if selectedBootVersion == nil || !bootVersions.contains(selectedBootVersion!) {
            selectedBootVersion = bootVersions.first
        }
    }

    private func completeBootSet(at directory: URL, identifier: String) -> Bool {
        let manager = FileManager.default
        func has(_ name: String) -> Bool { manager.fileExists(atPath: directory.appendingPathComponent(name).path) }
        if identifier.hasPrefix("iPhone11,") || identifier.hasPrefix("iPhone12,") || identifier.hasPrefix("iPad11,") {
            return has("iBSS.boot")
        }
        if identifier.hasPrefix("iPhone10,") { return has("iBSS.img4") }
        guard has("iBSS.img4"), has("iBEC.img4"), has("DeviceTree.img4"), has("Kernelcache.img4") else { return false }
        let major = Int(directory.lastPathComponent.split(separator: ".").first ?? "0") ?? 0
        return !(12...15).contains(major) || has("Trustcache.img4")
    }

    private func beginOperation() {
        if demoMode {
            beginDemoRestore()
            return
        }
        guard let engine = engineURL else { return }
        if operation != .justBoot {
            let alert = NSAlert()
            alert.messageText = "Erase and restore this device?"
            alert.informativeText = "This cannot be undone. Keep the phone connected until surrealra1n finishes."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Start Restore")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        logWindow.clear()
        inlineLogRenderer.clear()
        liveTranscript = ""
        currentProgress = 0
        currentStage = "Starting surrealra1n"
        currentOutputLine = "Launching surrealra1n…"
        step = .running
        render()
        do {
            try restoreSession.start(
                engine: engine,
                target: targetURL,
                base: baseURL,
                shsh: shshURL,
                bootVersion: selectedBootVersion,
                deviceIdentifier: device?.identifier ?? "",
                operation: operation
            )
        } catch {
            finishedCode = -1
            appendLog("\nGUI error: \(error.localizedDescription)\n")
            step = .finished
            render()
        }
    }

    private func confirmCancel() {
        let alert = NSAlert()
        alert.messageText = "Stop the current operation?"
        alert.informativeText = demoMode ? "This stops only the fake UI demonstration." : "Stopping during a restore can leave the device in Recovery or DFU mode."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Stop")
        if alert.runModal() == .alertSecondButtonReturn {
            if demoMode {
                demoTimer?.invalidate()
                demoTimer = nil
                finishedCode = 130
                step = .finished
                render()
            } else {
                restoreSession.cancel()
            }
        }
    }

    private func answerPrompt(positive: Bool) {
        guard let prompt = currentPrompt else { return }
        let textResponse = promptTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if demoMode {
            currentPrompt = nil
            switch prompt {
            case .recoveryReady:
                startDemoDFUSequence()
            case .pwnedReady:
                appendLog("Device is pwned!\n")
                continueDemoAfterPwn()
            case .textInput:
                showDemoPrompt(.recoveryReady, after: 0.35)
            case .rebuildFiles, .yesNo(_), .continueOnly(_):
                startDemoOperationProgress()
            }
            return
        }
        if positive {
            switch prompt {
            case .rebuildFiles, .yesNo: restoreSession.respond("y")
            case .textInput: restoreSession.respond(textResponse)
            default: restoreSession.respond("")
            }
        } else {
            restoreSession.respond("n")
        }
        currentPrompt = nil
        step = .running
        render()
    }

    private func beginDemoRestore() {
        let alert = NSAlert()
        alert.messageText = operation == .justBoot ? "Begin the fake boot?" : "Begin the fake restore?"
        alert.informativeText = "This is UI Demo Mode. No device, sudo, IPSW, or surrealra1n command will be used."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start Demo")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        logWindow.clear()
        inlineLogRenderer.clear()
        liveTranscript = ""
        appendLog("[demo] UI Demo Mode started\n[demo] No device commands will run\n")
        currentProgress = 0.02
        currentStage = operation == .justBoot ? "Checking saved boot files" : "Preparing restore"
        currentOutputLine = currentStage
        step = .running
        render()
        showDemoPrompt(.recoveryReady, after: 0.8)
    }

    private func showDemoPrompt(_ prompt: RestorePrompt, after delay: TimeInterval) {
        scheduleDemo(after: delay) { [weak self] in
            guard let self = self else { return }
            self.currentPrompt = prompt
            self.step = .handoff
            self.appendLog("[demo] Waiting for \(self.handoffTitle.lowercased())\n")
            self.render()
        }
    }

    private func startDemoDFUSequence() {
        var stages = stride(from: 3, through: 1, by: -1).map { ("Get ready  (\($0))", "\($0)\n") }
        stages[0].1 = "Instructions will begin in:\n" + stages[0].1
        if dfuProfile.secondInstruction.localizedCaseInsensitiveContains("volume down") {
            let both = stride(from: 4, through: 1, by: -1).map { ("Hold Side + Volume Down  (\($0))", "\($0)\n") }
            let release = stride(from: 8, through: 1, by: -1).map { ("Release Side, keep holding Volume Down  (\($0))", "\($0)\n") }
            stages += both
            stages[3].1 = "Hold volume down + power buttons.\n" + stages[3].1
            stages += release
            stages[7].1 = "Release the power button now, but keep holding volume down button.\n" + stages[7].1
        } else {
            let both = stride(from: 10, through: 1, by: -1).map { ("Hold Power + Home  (\($0))", "\($0)\n") }
            let release = stride(from: 5, through: 1, by: -1).map { ("Release Power, keep holding Home  (\($0))", "\($0)\n") }
            stages += both
            stages[3].1 = "Hold power + home buttons.\n" + stages[3].1
            stages += release
            stages[13].1 = "Release the power button now, but keep holding home button.\n" + stages[13].1
        }
        runDemoDFUStage(stages, index: 0)
    }

    private func runDemoDFUStage(_ stages: [(String, String)], index: Int) {
        guard index < stages.count else {
            appendLog("Checking for DFU devices\nThe device has entered DFU successfully!\n")
            if requiresExternalPwn {
                appendLog("Checking if this device is in pwned DFU already\n")
                showDemoPrompt(.pwnedReady, after: 0.45)
            } else {
                appendLog("Checking if this device is in pwned DFU already\nDevice is not pwned yet, attempting to pwn\nChecking if this device has pwned successfully\nDevice is pwned!\n")
                continueDemoAfterPwn()
            }
            return
        }
        currentStage = stages[index].0
        currentProgress = 0.08 + Double(index) / Double(stages.count) * 0.06
        appendLog(stages[index].1)
        step = .dfuSequence
        render()
        scheduleDemo(after: 1.0) { [weak self] in self?.runDemoDFUStage(stages, index: index + 1) }
    }

    private func continueDemoAfterPwn() {
        if operation == .tetheredRestore {
            appendLog("Fetching shsh blobs for the currently signed iOS version\nRestore files already exist\n")
            showDemoPrompt(.rebuildFiles, after: 0.45)
        } else {
            startDemoOperationProgress()
        }
    }

    private func startDemoOperationProgress() {
        let identifier = device?.identifier ?? demoIdentifier
        let stages: [(Double, String)]
        switch operation {
        case .justBoot:
            if identifier.hasPrefix("iPhone10,") || identifier.hasPrefix("iPhone11,") || identifier.hasPrefix("iPhone12,") || identifier.hasPrefix("iPad11,") {
                stages = [(0.70, "Sending iBSS"), (1.00, "Device should now boot")]
            } else {
                stages = [
                    (0.58, "Sending iBSS"), (0.68, "Sending iBEC"), (0.78, "Sending DeviceTree"),
                    (0.88, "Sending trustcache"), (0.96, "Sending Kernelcache"), (1.00, "Device should now boot")
                ]
            }
        case .restoreWithBlobs:
            stages = [(0.42, "Preparing iBSS and iBEC for futurerestore"), (0.64, "Starting futurerestore"), (1.00, "Restore has completed! Read above if there is any errors")]
        case .untethered1033:
            stages = [(0.28, "Downloading the signed 10.3.3 OTA SEP"), (0.42, "Saving the 10.3.3 OTA SHSH ticket"), (0.64, "Starting futurerestore"), (1.00, "Restore has completed! Read above if there are any errors")]
        case .tetheredRestore:
            stages = [(0.28, "Making new restore files"), (0.48, "Building the custom IPSW and boot files"), (0.64, "Starting futurerestore"), (1.00, "Restore has completed! Read above if there is any errors")]
        }
        runDemoProgressStage(stages, index: 0)
    }

    private func runDemoProgressStage(_ stages: [(Double, String)], index: Int) {
        guard index < stages.count else {
            demoTimer = nil
            finishedCode = 0
            step = .finished
            render()
            return
        }
        currentProgress = stages[index].0
        currentStage = stages[index].1
        appendLog(stages[index].1 + "\n")
        step = .running
        render()
        scheduleDemo(after: 1.0) { [weak self] in self?.runDemoProgressStage(stages, index: index + 1) }
    }

    private func scheduleDemo(after delay: TimeInterval, action: @escaping () -> Void) {
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in action() }
    }

    private var handoffTitle: String {
        switch currentPrompt {
        case .recoveryReady: return "Put the device into Recovery"
        case .pwnedReady: return "Pwn the device with usbliter8"
        case .rebuildFiles: return "Restore files already exist"
        case .yesNo: return "surrealra1n needs a choice"
        case .continueOnly: return "Continue the restore"
        case .textInput: return "Enter the installed iOS version"
        case .none: return "Device handoff"
        }
    }

    private var handoffInstructions: String {
        switch currentPrompt {
        case .recoveryReady:
            return "Connect the device and put it into Recovery mode using its normal recovery button sequence.\n\nClick Continue when the recovery screen appears. The timed DFU instructions for this exact device family will then begin."
        case .pwnedReady:
            return "Disconnect the iPhone, pwn it with the usbliter8 Pico, then reconnect it to this Mac.\n\nContinue only after the pwn step reports success."
        case .rebuildFiles:
            return "Previously built restore files were found. Rebuild them from the IPSWs selected in this session, or reuse the existing files."
        case .yesNo(let message), .continueOnly(let message):
            return message
        case .textInput(let message):
            return message
        case .none:
            return "Follow the instructions before continuing."
        }
    }

    private var handoffButtonTitle: String {
        switch currentPrompt {
        case .recoveryReady: return "Continue"
        case .pwnedReady: return "Device Is Pwned"
        case .rebuildFiles: return "Rebuild"
        case .yesNo: return "Yes"
        case .textInput: return "Continue"
        default: return "Continue"
        }
    }

    private var promptHasNegativeChoice: Bool {
        switch currentPrompt {
        case .rebuildFiles, .yesNo: return true
        default: return false
        }
    }

    private func showLogs() {
        logWindow.present()
    }

    @objc private func retryEngineDownload() { prepareEngine() }
    @objc private func toggleErrorLogs(_ sender: NSButton) { showLogsOnError = sender.state == .on }

    @objc private func chooseBootchainsDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Bootchain Library"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if FileManager.default.fileExists(atPath: engineWorkspace.bootchainsDirectory.path) {
            panel.directoryURL = engineWorkspace.bootchainsDirectory
        }
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        changeBootchainsDirectory(to: directory)
    }

    @objc private func resetBootchainsDirectory() {
        changeBootchainsDirectory(to: EngineWorkspace.defaultBootchainsDirectory)
    }

    private func changeBootchainsDirectory(to directory: URL) {
        let destination = directory.standardizedFileURL
        guard destination != engineWorkspace.bootchainsDirectory.standardizedFileURL else { return }
        let alert = NSAlert()
        alert.messageText = "Change the bootchain library?"
        alert.informativeText = "New restores and imported bootchains will use this folder. Existing bootchains can be copied without deleting the originals."
        alert.addButton(withTitle: "Copy Existing")
        alert.addButton(withTitle: "Use Empty/Existing Folder")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return }
        do {
            try engineWorkspace.useBootchainsDirectory(destination, copyExisting: response == .alertFirstButtonReturn)
            selectedBootVersion = nil
            bootVersions = []
            render()
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Could not change the bootchain library"
            failure.runModal()
        }
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home + "/") ? "~" + String(url.path.dropFirst(home.count)) : url.path
    }

    @objc private func toggleDemoMode(_ sender: NSButton) {
        guard developerDemoEnabled else { return }
        demoMode = sender.state == .on
        demoTimer?.invalidate()
        demoTimer = nil
        if demoMode {
            deviceObserver.stop()
            applyDemoDevice()
        } else {
            device = nil
            targetURL = nil
            baseURL = nil
            shshURL = nil
            deviceObserver.start()
        }
        render()
    }

    @objc private func selectDemoDevice(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        demoIdentifier = demoDevices[sender.indexOfSelectedItem].0
        if demoMode { applyDemoDevice() }
    }

    private func applyDemoDevice() {
        let selected = demoDevices.first(where: { $0.0 == demoIdentifier }) ?? demoDevices[15]
        device = ConnectedDevice(name: "Fake \(selected.1.components(separatedBy: " (").first ?? selected.1)", identifier: selected.0, ecid: "DEMO000000000001", mode: "Normal")
        targetURL = URL(fileURLWithPath: "/Demo/\(selected.0)_target_Restore.ipsw")
        baseURL = URL(fileURLWithPath: "/Demo/\(selected.0)_latest_signed_Base.ipsw")
        shshURL = URL(fileURLWithPath: "/Demo/\(selected.0)_target.shsh2")
        if step == .welcome || step == .options { render() }
    }

    @objc private func selectTarget() { chooseIPSW(title: "Choose target IPSW") { targetURL = $0; render() } }
    @objc private func selectBase() { chooseIPSW(title: "Choose currently signed base IPSW") { baseURL = $0; render() } }
    @objc private func selectSHSH() {
        let panel = NSOpenPanel()
        panel.title = "Choose SHSH2 ticket"
        panel.allowedContentTypes = [UTType(filenameExtension: "shsh2") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { shshURL = url; render() }
    }

    private func chooseIPSW(title: String, completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [UTType(filenameExtension: "ipsw") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }

    private func prepareEngine() {
        engineURL = nil
        engineDownloadFailed = false
        engineWorkspace.prepare(status: { [weak self] status in
            self?.engineStatus = status
            if self?.step == .options { self?.render() }
        }, completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let url):
                self.engineURL = url
                self.deviceObserver.engineURL = url
                self.engineStatus = "Latest surrealra1n is ready."
                self.engineDownloadFailed = false
            case .failure(let error):
                self.engineURL = nil
                self.engineStatus = error.localizedDescription
                self.engineDownloadFailed = true
            }
            if self.step == .welcome || self.step == .options { self.render() }
        })
    }

    private func heading(_ text: String) -> NSTextField {
        let field = label(text, size: 14, weight: .bold)
        field.font = InterfaceTheme.heading
        return field
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil, wrapping: Bool = false) -> NSTextField {
        let field = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        if size > 20 { field.font = NSFont.systemFont(ofSize: size, weight: weight) }
        else if size <= 12 { field.font = weight == .regular ? InterfaceTheme.detail : InterfaceTheme.detailStrong }
        else if weight == .regular { field.font = InterfaceTheme.body }
        else { field.font = InterfaceTheme.bodyStrong }
        field.textColor = color ?? InterfaceTheme.foreground
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func actionButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = InterfaceTheme.button
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func radioButton(_ title: String, selected: Bool, action: Selector) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: self, action: action)
        button.state = selected ? .on : .off
        button.controlSize = .regular
        button.font = InterfaceTheme.body
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func appendLog(_ text: String) {
        logWindow.append(text)
        liveTranscript = inlineLogRenderer.feed(text)
        if let console = liveConsoleView {
            console.string = liveTranscript
            console.scrollToEndOfDocument(nil)
        }
    }

    private var dfuProfile: DFUInstructions {
        DFUInstructions.profile(for: device?.identifier ?? "iPhone12,3")
    }

    private var requiresExternalPwn: Bool {
        guard let identifier = device?.identifier else { return false }
        return identifier.hasPrefix("iPhone11,") || identifier.hasPrefix("iPhone12,") || identifier.hasPrefix("iPad11,")
    }

    private func phoneArtwork(named assetName: String) -> NSImageView {
        let view = NSImageView()
        if let url = Bundle.main.url(forResource: assetName, withExtension: "png") {
            view.image = NSImage(contentsOf: url)
        }
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func calloutConstraint(_ label: NSView, relativeTo phone: NSView, position: DFUInstructions.CalloutPosition) -> NSLayoutConstraint {
        switch position {
        case .volumeButton: return label.centerYAnchor.constraint(equalTo: phone.topAnchor, constant: 61)
        case .sideButton: return label.centerYAnchor.constraint(equalTo: phone.topAnchor, constant: 61)
        case .top: return label.centerYAnchor.constraint(equalTo: phone.topAnchor, constant: 9)
        case .home: return label.centerYAnchor.constraint(equalTo: phone.bottomAnchor, constant: -14)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "surrealra1n"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    func restoreSession(_ session: RestoreSession, received text: String) {
        appendLog(text)
        if let line = liveTranscript.components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            currentOutputLine = line.trimmingCharacters(in: .whitespaces)
            liveOutputLabel?.stringValue = currentOutputLine
        }
    }

    func restoreSession(_ session: RestoreSession, didAdvanceTo stage: String, progress: Double) {
        if stage.hasPrefix("DFU: ") {
            currentStage = String(stage.dropFirst(5))
            step = .dfuSequence
        } else {
            currentStage = stage
            if step == .dfuSequence { step = .running }
        }
        currentProgress = progress
        if step == .running || step == .dfuSequence { render() }
    }

    func restoreSession(_ session: RestoreSession, requests prompt: RestorePrompt) {
        currentPrompt = prompt
        step = .handoff
        render()
    }

    func restoreSession(_ session: RestoreSession, didFinishWith code: Int32) {
        finishedCode = code
        currentPrompt = nil
        step = .finished
        render()
        if code != 0 && showLogsOnError { showLogs() }
    }

    var hasRunningOperation: Bool { restoreSession.isRunning || demoTimer != nil }
    func stopRunningOperation() {
        demoTimer?.invalidate()
        demoTimer = nil
        restoreSession.cancel()
    }
    func cleanupSession() {
        demoTimer?.invalidate()
        demoTimer = nil
        engineWorkspace.cleanup()
    }
}

final class PhoneOutlineView: NSView {
    var connected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let body = bounds.insetBy(dx: 6, dy: 2)
        let path = NSBezierPath(roundedRect: body, xRadius: min(18, body.width / 5), yRadius: min(18, body.width / 5))
        (connected ? NSColor(calibratedRed: 0.25, green: 0.67, blue: 0.98, alpha: 1) : NSColor(calibratedWhite: 0.48, alpha: 1)).setStroke()
        path.lineWidth = 2
        path.stroke()
        let screen = body.insetBy(dx: 5, dy: 9)
        NSColor(calibratedWhite: connected ? 0.15 : 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: screen, xRadius: 11, yRadius: 11).fill()
        let notch = NSBezierPath(roundedRect: NSRect(x: bounds.midX - body.width * 0.18, y: body.maxY - 10, width: body.width * 0.36, height: 5), xRadius: 2.5, yRadius: 2.5)
        NSColor(calibratedWhite: 0.38, alpha: 1).setFill()
        notch.fill()
    }
}

final class LogoView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        EmojiLogo.draw(in: bounds)
    }
}

enum EmojiLogo {
    static let symbol = "⚡️"

    static func draw(in rect: NSRect) {
        let fontSize = min(rect.width, rect.height) * 0.82
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .paragraphStyle: centeredParagraphStyle
        ]
        let attributed = NSAttributedString(string: symbol, attributes: attributes)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }

    static func image(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        return image
    }

    private static var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }
}
