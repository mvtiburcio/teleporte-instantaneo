import Foundation

/// Evento do motor (uma linha JSON do stdout). Campos ausentes ficam nil.
struct EngineEvent: Decodable, Sendable {
    let event: String
    var version: Int?
    var hidden: Bool?
    var bgReady: Bool?
    var bgCountdown: Double?
    var gesture: Bool?
    var fps: Double?
    var rms: Double?
    var code: String?
    var msg: String?

    static func parse(_ line: String) -> EngineEvent? {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try? d.decode(EngineEvent.self, from: Data(line.utf8))
    }
}

/// Sobe o motor (teleporte.py --ipc) como processo filho: comandos no stdin, eventos no stdout, stderr no log.
final class EngineClient: @unchecked Sendable {
    var onEvent: @MainActor (EngineEvent) -> Void = { _ in }
    var onExit: @MainActor (Int32) -> Void = { _ in }
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var pending = Data()  // só mexido na fila do readabilityHandler

    /// Executável e argumentos do motor: empacotado no app (release) ou o .venv do repositório (desenvolvimento).
    static func command(repoDir: String? = Bundle.main.object(forInfoDictionaryKey: "IlusioRepoDir") as? String) -> (URL, [String])? {
        if let bundled = Bundle.main.url(forResource: "ilusio-engine", withExtension: nil, subdirectory: "engine") {
            return (bundled, ["--ipc"])
        }
        guard let repoDir, !repoDir.isEmpty else { return nil }
        let repo = URL(fileURLWithPath: repoDir).standardizedFileURL
        // numa worktree (.worktrees/x) o .venv fica no checkout principal
        // standardizar só a pasta: com "..", o standardizedFileURL resolve symlinks e o .venv/bin/python
        // viraria o python do Homebrew, fora do venv (sem numpy)
        let python = [repo, repo.appendingPathComponent("../..").standardizedFileURL]
            .map { $0.appendingPathComponent(".venv/bin/python") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let python else { return nil }
        return (python, [repo.appendingPathComponent("teleporte.py").path, "--ipc"])
    }

    func start(executable: URL, arguments: [String], log: URL) throws {
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let logHandle = try FileHandle(forWritingTo: log)
        logHandle.seekToEndOfFile()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = logHandle
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil  // EOF: o motor saiu; sem isso o handler roda em laço
                return
            }
            guard let self else { return }
            pending.append(data)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...nl)
                guard let ev = EngineEvent.parse(line) else { continue }
                DispatchQueue.main.async { MainActor.assumeIsolated { self.onEvent(ev) } }
            }
        }
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onExit(p.terminationStatus) } }
        }
        try process.run()
    }

    func send(_ cmd: String, _ fields: [String: Any] = [:]) {
        var msg = fields
        msg["cmd"] = cmd
        guard process.isRunning, let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        try? input.fileHandleForWriting.write(contentsOf: data + Data([0x0A]))  // motor morto: EPIPE vira erro ignorado
    }

    /// Pede pra sair; se em 2 s o motor não saiu, encerra à força.
    func stop() {
        send("stop")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { process.terminate() }
        }
    }
}
