import AVFoundation
import Observation
import SwiftUI

/// Estado do app: liga câmera + motor, repassa comandos e mantém a prévia (slot out a 15 fps).
@MainActor @Observable
final class AppModel {
    static let width = 1280, height = 720
    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Teleporte")
    static let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Teleporte/engine.log")

    var running = false
    var state: EngineEvent?
    var preview: CGImage?
    var lastError: String?
    var cameraID: String?

    @ObservationIgnored private var engine: EngineClient?
    @ObservationIgnored private var capture: CameraCapture?
    @ObservationIgnored private var frames: FrameBuffer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastOut: UInt64 = 0
    @ObservationIgnored private var outBytes = [UInt8](repeating: 0, count: width * height * 4)

    func toggleRunning() async {
        if running { stop() } else { await start() }
    }

    func start() async {
        lastError = nil
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            lastError = "Sem permissão de câmera: libere em Ajustes > Privacidade e Segurança > Câmera."
            return
        }
        guard let id = cameraID ?? CameraCapture.cameras().first?.uniqueID else {
            lastError = "Nenhuma câmera encontrada."
            return
        }
        guard let (exe, args) = EngineClient.command() else {
            lastError = "Motor não encontrado: rode ./setup.sh no repositório."
            return
        }
        do {
            try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
            let shm = Self.supportDir.appendingPathComponent("frames.shm").path
            let frames = try FrameBuffer(path: shm, width: Self.width, height: Self.height)
            let capture = CameraCapture(buffer: frames)
            try capture.start(deviceID: id)
            let engine = EngineClient()
            let current = ObjectIdentifier(engine)
            engine.onEvent = { [weak self] in self?.handle($0) }
            engine.onExit = { [weak self] code in
                guard let self, let e = self.engine, ObjectIdentifier(e) == current else { return }  // motor antigo saindo
                stop()
                lastError = "O motor parou (código \(code)). Detalhes em \(Self.logURL.path)."
            }
            try engine.start(executable: exe, arguments: args, log: Self.logURL)
            engine.send("start", ["shm": shm])
            (self.frames, self.capture, self.engine, cameraID) = (frames, capture, engine, id)
            running = true
            lastOut = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPreview() }
            }
        } catch {
            capture?.stop()
            lastError = error.localizedDescription
        }
    }

    func stop() {
        timer?.invalidate()
        engine?.stop()
        capture?.stop()
        (timer, engine, capture, frames) = (nil, nil, nil, nil)
        running = false
        state = nil
        preview = nil
    }

    func send(_ cmd: String, _ fields: [String: Any] = [:]) {
        engine?.send(cmd, fields)
    }

    private func handle(_ ev: EngineEvent) {
        switch ev.event {
        case "state": state = ev
        case "error": lastError = ev.msg ?? ev.code
        default: break
        }
    }

    private func refreshPreview() {
        guard let frames else { return }
        let ok = outBytes.withUnsafeMutableBytes { frames.read(.output, last: &lastOut, into: $0.baseAddress!) }
        if ok { preview = Self.image(outBytes, width: Self.width, height: Self.height) }
    }

    nonisolated static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
