import Foundation

final class EngineWorkspace {
    private static let bootchainsPreferenceKey = "BootchainsDirectory"
    private let archiveURL = URL(string: "https://github.com/pwnerblu/surrealra1n/archive/refs/heads/development.zip")!
    private var downloadTask: URLSessionDownloadTask?
    private(set) var sessionRoot: URL?
    private(set) var engineURL: URL?
    private(set) var bootchainsDirectory: URL

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: Self.bootchainsPreferenceKey), !savedPath.isEmpty {
            bootchainsDirectory = URL(fileURLWithPath: savedPath, isDirectory: true).standardizedFileURL
        } else {
            bootchainsDirectory = Self.defaultBootchainsDirectory
        }
    }

    static var defaultBootchainsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Surrealra1nGUI/boot", isDirectory: true)
    }

    func prepare(status: @escaping (String) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        cleanup()
        status("Downloading the latest surrealra1n…")

        downloadTask = URLSession.shared.downloadTask(with: archiveURL) { [weak self] temporaryURL, response, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let error = NSError(domain: "Surrealra1nGUI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode)."])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let temporaryURL = temporaryURL else {
                let error = NSError(domain: "Surrealra1nGUI", code: 10, userInfo: [NSLocalizedDescriptionKey: "The surrealra1n download did not produce a file."])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("surrealra1n-gui-\(UUID().uuidString)", isDirectory: true)
                let archive = root.appendingPathComponent("surrealra1n.zip")
                let unpacked = root.appendingPathComponent("source", isDirectory: true)
                try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: temporaryURL, to: archive)
                self.sessionRoot = root

                DispatchQueue.main.async { status("Unpacking surrealra1n…") }
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-x", "-k", archive.path, unpacked.path]
                try ditto.run()
                ditto.waitUntilExit()
                guard ditto.terminationStatus == 0 else {
                    throw NSError(domain: "Surrealra1nGUI", code: 11, userInfo: [NSLocalizedDescriptionKey: "The downloaded surrealra1n archive could not be unpacked."])
                }

                guard let engine = self.findEngine(in: unpacked) else {
                    throw NSError(domain: "Surrealra1nGUI", code: 12, userInfo: [NSLocalizedDescriptionKey: "The downloaded archive does not contain surrealra1n.sh."])
                }
                self.engineURL = engine
                try self.attachPersistentGeneratedFiles(to: engine)
                DispatchQueue.main.async { completion(.success(engine)) }
            } catch {
                self.cleanup()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        downloadTask?.resume()
    }

    func cleanup() {
        downloadTask?.cancel()
        downloadTask = nil
        if let root = sessionRoot { try? FileManager.default.removeItem(at: root) }
        sessionRoot = nil
        engineURL = nil
    }

    func importBootchainVersion(from source: URL, identifier: String, version: String) throws {
        guard !identifier.isEmpty, !version.isEmpty, !identifier.contains("/"), !version.contains("/") else {
            throw NSError(domain: "Surrealra1nGUI", code: 16, userInfo: [NSLocalizedDescriptionKey: "The bootchain device or version name is invalid."])
        }
        let destination = bootchainsDirectory
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .standardizedFileURL
        if source.standardizedFileURL != destination {
            try mergeContents(from: source.standardizedFileURL, into: destination)
        }
    }

    func useBootchainsDirectory(_ directory: URL, copyExisting: Bool) throws {
        let manager = FileManager.default
        let source = bootchainsDirectory.standardizedFileURL
        let destination = directory.standardizedFileURL
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)

        if copyExisting && source != destination && manager.fileExists(atPath: source.path) {
            let nested = destination.path.hasPrefix(source.path + "/") || source.path.hasPrefix(destination.path + "/")
            guard !nested else {
                throw NSError(domain: "Surrealra1nGUI", code: 15, userInfo: [NSLocalizedDescriptionKey: "Choose a folder outside the current bootchain library when copying existing files."])
            }
            try mergeContents(from: source, into: destination)
        }

        bootchainsDirectory = destination
        if destination == Self.defaultBootchainsDirectory.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: Self.bootchainsPreferenceKey)
        } else {
            UserDefaults.standard.set(destination.path, forKey: Self.bootchainsPreferenceKey)
        }
        if let engineURL = engineURL { try attachPersistentGeneratedFiles(to: engineURL) }
    }

    private func findEngine(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let file as URL in enumerator where file.lastPathComponent == "surrealra1n.sh" {
            return file.deletingLastPathComponent()
        }
        return nil
    }

    private func attachPersistentGeneratedFiles(to engine: URL) throws {
        let manager = FileManager.default
        guard let applicationSupport = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "Surrealra1nGUI", code: 13, userInfo: [NSLocalizedDescriptionKey: "The Application Support directory is unavailable."])
        }
        let stateRoot = applicationSupport.appendingPathComponent("Surrealra1nGUI", isDirectory: true)
        try manager.createDirectory(at: stateRoot, withIntermediateDirectories: true)

        for name in ["boot", "restorefiles"] {
            let persistent = name == "boot" ? bootchainsDirectory : stateRoot.appendingPathComponent(name, isDirectory: true)
            try manager.createDirectory(at: persistent, withIntermediateDirectories: true)
            let sessionPath = engine.appendingPathComponent(name, isDirectory: true)
            if manager.fileExists(atPath: sessionPath.path) || (try? manager.destinationOfSymbolicLink(atPath: sessionPath.path)) != nil {
                try manager.removeItem(at: sessionPath)
            }
            try manager.createSymbolicLink(at: sessionPath, withDestinationURL: persistent)
        }
    }

    private func mergeContents(from source: URL, into destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = (try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                try mergeContents(from: item, into: target)
            } else if !manager.fileExists(atPath: target.path) {
                try manager.copyItem(at: item, to: target)
            }
        }
    }
}
