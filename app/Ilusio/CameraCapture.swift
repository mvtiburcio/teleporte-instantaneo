import AVFoundation

enum CaptureError: LocalizedError {
    case notFound, unsupported
    var errorDescription: String? {
        switch self {
        case .notFound: "Câmera não encontrada."
        case .unsupported: "Esta câmera não aceita o formato de vídeo do Ilusio."
        }
    }
}

/// Captura a câmera escolhida (ver Devices) em BGRA no tamanho do FrameBuffer e escreve cada frame no slot in.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ilusio.camera")
    private let buffer: FrameBuffer

    init(buffer: FrameBuffer) {
        self.buffer = buffer
    }

    struct FormatInfo: Equatable {
        let width: Int32, height: Int32, maxFPS: Double
    }

    /// Formato da câmera pra uma taxa: o menor HD (≥ 1280x720) que aguenta a fps; senão o HD mais rápido;
    /// sem HD, o maior que houver. Resolução vem antes de fps: o motor trabalha em 720p.
    static func pickFormat(_ formats: [FormatInfo], fps: Double) -> Int? {
        let area = { (i: Int) in Int(formats[i].width) * Int(formats[i].height) }
        let hd = formats.indices.filter { formats[$0].width >= 1280 && formats[$0].height >= 720 }
        if let i = hd.filter({ formats[$0].maxFPS >= fps }).min(by: { area($0) < area($1) }) { return i }
        if let i = hd.max(by: { formats[$0].maxFPS < formats[$1].maxFPS }) { return i }
        return formats.indices.max(by: { area($0) < area($1) })
    }

    /// fps aceita pela câmera mais perto da pedida, dentro de uma das faixas do formato (fora delas o
    /// AVFoundation lança exceção e o app fecha).
    static func clampFPS(_ fps: Double, ranges: [(min: Double, max: Double)]) -> Double {
        if ranges.contains(where: { $0.min <= fps && fps <= $0.max }) { return fps }
        let candidates = ranges.flatMap { [$0.min, $0.max] }
        return candidates.min(by: { abs($0 - fps) < abs($1 - fps) }) ?? fps
    }

    /// Maior fps que a câmera entrega em HD, sem ligar nada (pro aviso na aba Câmera e mic).
    static func maxFPS(deviceID: String, wanted: Double) -> Double? {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { return nil }
        let infos = device.formats.map(info)
        return pickFormat(infos, fps: wanted).map { min(wanted, infos[$0].maxFPS) }
    }

    private static func info(_ f: AVCaptureDevice.Format) -> FormatInfo {
        let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        return FormatInfo(width: d.width, height: d.height, maxFPS: f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30)
    }

    /// Liga (ou reconfigura) a captura; devolve a fps que a câmera vai entregar de fato.
    @discardableResult
    func start(deviceID: String, fps: Double = 30) throws -> Double {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { throw CaptureError.notFound }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [  // o próprio AVFoundation escala pro tamanho do motor
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: buffer.width,
            kCVPixelBufferHeightKey as String: buffer.height,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach { session.removeInput($0) }  // trocar de câmera com a sessão rodando
        session.outputs.forEach { session.removeOutput($0) }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CaptureError.unsupported }
        session.addInput(input)
        session.addOutput(output)
        let delivered = configure(device, fps: fps)
        queue.async { self.session.startRunning() }
        return delivered
    }

    private func configure(_ device: AVCaptureDevice, fps: Double) -> Double {
        let infos = device.formats.map(Self.info)
        guard let index = Self.pickFormat(infos, fps: fps), (try? device.lockForConfiguration()) != nil else { return min(fps, 30) }
        defer { device.unlockForConfiguration() }
        let format = device.formats[index]
        let rate = Self.clampFPS(fps, ranges: format.videoSupportedFrameRateRanges.map { ($0.minFrameRate, $0.maxFrameRate) })
        device.activeFormat = format
        let duration = CMTime(value: 1, timescale: CMTimeScale(rate.rounded()))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        return rate
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard CVPixelBufferGetWidth(px) == buffer.width, CVPixelBufferGetHeight(px) == buffer.height,
              let src = CVPixelBufferGetBaseAddress(px) else { return }
        buffer.write(.input, from: src, bytesPerRow: CVPixelBufferGetBytesPerRow(px))
    }
}
