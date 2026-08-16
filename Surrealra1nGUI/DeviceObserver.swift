import Foundation

struct ConnectedDevice {
    let name: String
    let identifier: String
    let ecid: String
    let mode: String
}

final class DeviceObserver {
    var onUpdate: ((ConnectedDevice?) -> Void)?
    private var timer: DispatchSourceTimer?
    var engineURL: URL?

    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func scan() {
        if let normal = run("/usr/bin/env", ["ideviceinfo"]), normal.contains("ProductType:") {
            let identifier = value("ProductType", in: normal)
            let ecid = value("UniqueChipID", in: normal)
            let name = value("DeviceName", in: normal)
            publish(ConnectedDevice(name: name.isEmpty ? friendlyName(identifier) : name, identifier: identifier, ecid: ecid, mode: "Normal"))
            return
        }

        let bundled = engineURL?.appendingPathComponent("bin/irecovery").path
        let executable = (bundled != nil && FileManager.default.isExecutableFile(atPath: bundled!)) ? bundled! : "/usr/bin/env"
        let arguments = executable == "/usr/bin/env" ? ["irecovery", "-q"] : ["-q"]
        if let recovery = run(executable, arguments), recovery.contains("ECID:") {
            let product = value("PRODUCT", in: recovery)
            let mode = recovery.contains("MODE: DFU") ? "DFU" : "Recovery/DFU"
            publish(ConnectedDevice(name: friendlyName(product), identifier: product, ecid: value("ECID", in: recovery), mode: mode))
            return
        }
        publish(nil)
    }

    private func run(_ executable: String, _ arguments: [String]) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = executable
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        task.environment = env
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func value(_ key: String, in text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix(key + ":") {
                return line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private func friendlyName(_ identifier: String) -> String {
        let names = [
            "iPhone6,1": "iPhone 5s", "iPhone6,2": "iPhone 5s",
            "iPhone7,1": "iPhone 6 Plus", "iPhone7,2": "iPhone 6",
            "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE (1st generation)",
            "iPhone9,1": "iPhone 7", "iPhone9,2": "iPhone 7 Plus", "iPhone9,3": "iPhone 7", "iPhone9,4": "iPhone 7 Plus",
            "iPhone10,1": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,3": "iPhone X",
            "iPhone10,4": "iPhone 8", "iPhone10,5": "iPhone 8 Plus", "iPhone10,6": "iPhone X",
            "iPhone11,4": "iPhone XS Max",
            "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd generation)",
            "iPhone11,2": "iPhone XS", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
            "iPad4,1": "iPad Air", "iPad4,2": "iPad Air", "iPad4,3": "iPad Air",
            "iPad4,4": "iPad mini 2", "iPad4,5": "iPad mini 2", "iPad4,6": "iPad mini 2",
            "iPad5,1": "iPad mini 4", "iPad5,2": "iPad mini 4",
            "iPad5,3": "iPad Air 2", "iPad5,4": "iPad Air 2",
            "iPad11,1": "iPad mini (5th generation)", "iPad11,2": "iPad mini (5th generation)",
            "iPad11,3": "iPad Air (3rd generation)", "iPad11,4": "iPad Air (3rd generation)",
            "iPod7,1": "iPod touch (6th generation)"
        ]
        return names[identifier] ?? (identifier.isEmpty ? "Apple device" : identifier)
    }

    private func publish(_ device: ConnectedDevice?) {
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(device) }
    }
}
