import AppKit
import AVFoundation
import CoreMediaIO
import Foundation
import SystemExtensions

/// Câmera virtual própria ("Ilusio Camera"): ativação da system extension e entrega dos frames no fluxo sink.
enum VirtualCamera {
    static let extensionID = "com.mvtiburcio.ilusio.camera"
    static let deviceName = "Ilusio Camera"

    /// A "Ilusio Camera" já foi aprovada alguma vez (o OBS não conta).
    static var isInstalled: Bool {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified)
            .devices.contains { $0.localizedName == deviceName }
    }

    /// Painel "Itens de Início e Extensões" dos Ajustes do Sistema, onde fica a aprovação de Extensões de Câmera.
    static let approvalSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    /// O macOS só ativa system extensions de apps que estão em /Applications.
    static var appIsInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }
}

/// Pede ao macOS pra instalar/atualizar a extensão; a pessoa aprova uma vez em Ajustes do Sistema.
final class CameraActivation: NSObject, OSSystemExtensionRequestDelegate {
    static let doneText = "Câmera do Ilusio ativada."
    static let approvalText = "Agora aprove em Ajustes do Sistema ▸ Geral ▸ Itens de Início e Extensões ▸ Extensões de Câmera."
    private let done: @MainActor (String) -> Void

    init(done: @escaping @MainActor (String) -> Void) {
        self.done = done
    }

    func submit() {
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: VirtualCamera.extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func report(_ text: String) {
        MainActor.assumeIsolated { done(text) }  // a fila do request é a main
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace  // versão nova do app atualiza a câmera
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        NSWorkspace.shared.open(VirtualCamera.approvalSettingsURL)  // já leva a pessoa até onde aprova
        report(Self.approvalText)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        report(result == .willCompleteAfterReboot ? "Reinicie o Mac para terminar de ativar a câmera." : Self.doneText)
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        report("Não deu pra ativar a câmera: \(error.localizedDescription)")
    }
}

/// Lado do app do fluxo sink: acha o dispositivo pela CoreMediaIO e enfileira os frames que a extensão repassa pra chamada.
final class CameraSink: @unchecked Sendable {
    private let deviceID: CMIOObjectID
    private let streamID: CMIOStreamID
    private let queue: CMSimpleQueue
    private var format: CMFormatDescription?

    /// nil se a "Ilusio Camera" não está instalada/aprovada.
    init?() {
        guard let device = Self.objects(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices)
                .first(where: { Self.name($0) == VirtualCamera.deviceName }) else { return nil }
        let streams = Self.objects(device, kCMIODevicePropertyStreams)
        // o sink é o fluxo de saída (direção 0); o de entrada (1) é o que a chamada lê
        guard let sink = streams.first(where: { Self.uint32($0, kCMIOStreamPropertyDirection) == 0 }) ?? streams.dropFirst().first
        else { return nil }
        var unmanaged: Unmanaged<CMSimpleQueue>?
        guard CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, &unmanaged) == noErr, let unmanaged else { return nil }
        deviceID = device
        streamID = sink
        queue = unmanaged.takeRetainedValue()
        guard CMIODeviceStartStream(device, sink) == noErr else { return nil }
    }

    deinit {
        CMIODeviceStopStream(deviceID, streamID)
    }

    /// Enfileira um frame; se a extensão ainda não consumiu os anteriores, descarta (melhor pular que atrasar).
    func send(_ pixelBuffer: CVPixelBuffer) {
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }
        if format == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &format)
        }
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sample).toOpaque())  // a extensão solta a referência
    }

    // MARK: CoreMediaIO (API em C)

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func objects(_ object: CMIOObjectID, _ selector: Int) -> [CMIOObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private static func name(_ object: CMIOObjectID) -> String? {
        var addr = address(kCMIOObjectPropertyName)
        var name: Unmanaged<CFString>?
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &name) == noErr
        else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func uint32(_ object: CMIOObjectID, _ selector: Int) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, 4, &used, &value) == noErr else { return nil }
        return value
    }
}

/// Lê o slot out a 30 fps e entrega cada frame novo à "Ilusio Camera".
final class CameraFeed: @unchecked Sendable {
    private let frames: FrameBuffer
    private let sink: CameraSink
    private let timer: DispatchSourceTimer
    private var pool: CVPixelBufferPool?
    private var last: UInt64 = 0  // leitor próprio: a prévia lê o mesmo slot com o seu próprio seq

    /// nil se a câmera própria não está instalada (aí o motor manda pro OBS).
    init?(frames: FrameBuffer) {
        guard let sink = CameraSink() else { return nil }
        self.frames = frames
        self.sink = sink
        let attributes: NSDictionary = [
            kCVPixelBufferWidthKey: frames.width,
            kCVPixelBufferHeightKey: frames.height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes, &pool)
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ilusio.camera-feed", qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: 1.0 / 120)  // 120 Hz: pega cada frame de até 60 fps sem atraso
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
    }

    func stop() {
        timer.cancel()
    }

    private func tick() {
        guard let pool, frames.hasNew(.output, last: last) else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ok = frames.read(.output, last: &last, into: CVPixelBufferGetBaseAddress(buffer)!,
                             bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        if ok { sink.send(buffer) }
    }
}
