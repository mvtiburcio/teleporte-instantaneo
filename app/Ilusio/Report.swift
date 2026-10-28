import AppKit
import AVFoundation

/// "Gerar relatório": junta o que o suporte precisa (versões, sistema, checklist, dispositivos e o fim do
/// registro do motor) num arquivo e na área de transferência, pra pessoa mandar sem abrir o Terminal.
enum Report {
    @MainActor
    static func text(model: AppModel) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let video = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                     mediaType: .video, position: .unspecified).devices.map(\.localizedName)
        let audio = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                                     position: .unspecified).devices.map(\.localizedName)
        let checks = SetupItem.allCases.map { "\($0): \(model.checks.isDone($0) ? "ok" : "pendente")" }
        return """
        Ilusio \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(sysctl("hw.machine")), \(sysctl("hw.model"))
        Erro na tela: \(model.lastError ?? "nenhum")
        Checklist: \(checks.joined(separator: ", "))
        Ilusio Mic instalado: \(Bundle(path: VirtualMic.installedPath)?.infoDictionary?["CFBundleVersion"] as? String ?? "não")
        Câmeras: \(video.joined(separator: ", "))
        Microfones: \(audio.joined(separator: ", "))
        Extensões:
        \(run("/usr/bin/systemextensionsctl", ["list"]).split(separator: "\n").filter { $0.contains("ilusio") }.joined(separator: "\n"))

        Registro do motor (fim):
        \(logTail())
        """
    }

    /// Copia o relatório e salva ao lado do registro do motor, com o Finder já apontando pro arquivo
    /// (a Mesa pediria permissão de acesso a pastas).
    @MainActor
    static func save(model: AppModel) -> String {
        let body = text(model: model)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        let dir = AppModel.logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted).dateTimeSeparator(.space))
        let file = dir.appendingPathComponent("Relatório do Ilusio \(stamp).txt")
        guard (try? body.write(to: file, atomically: true, encoding: .utf8)) != nil else {
            return "Relatório copiado. Cole numa mensagem pra gente."
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
        return "Relatório copiado e aberto no Finder. Mande o arquivo pra gente."
    }

    // ponytail: 80 linhas cobrem o erro de partida do motor; mandar o arquivo inteiro se precisar de histórico
    private static func logTail(lines: Int = 80) -> String {
        guard let text = try? String(contentsOf: AppModel.logURL, encoding: .utf8) else { return "(sem registro)" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    private static func sysctl(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname(name, &value, &size, nil, 0)
        return String(cString: value)
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
