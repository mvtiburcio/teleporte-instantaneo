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

    func start(deviceID: String) throws {
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
        queue.async { self.session.startRunning() }
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
