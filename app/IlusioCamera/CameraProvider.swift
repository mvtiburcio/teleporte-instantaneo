import CoreMediaIO
import CoreText
import Foundation
import IOKit.audio
import os.log

// "Ilusio Camera": o app escreve os frames com o efeito no fluxo sink, e a extensão repassa pro fluxo
// source, que é o que a chamada vê. Sem frames do app, mostra um quadro de espera em vez de congelar.

let cameraName = "Ilusio Camera"
let frameRate = 30
let width: Int32 = 1280, height: Int32 = 720
private let log = Logger(subsystem: "com.mvtiburcio.ilusio.camera", category: "camera")

// UUIDs fixos: o Meet/Zoom lembram a câmera escolhida entre aberturas
private let deviceID = UUID(uuidString: "645E1B80-AC20-45ED-BF71-18161E495C7B")!
private let sourceID = UUID(uuidString: "3953E0A4-6377-40F2-A5D3-438402ACAB41")!
private let sinkID = UUID(uuidString: "565AC9EF-7945-4B9A-8612-824959A58C13")!

final class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var source: CameraStreamSource!
    private var sink: CameraStreamSource!
    private var format: CMFormatDescription!
    private var pool: CVPixelBufferPool!
    private let queue = DispatchQueue(label: "ilusio.camera", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var sourceClients = 0
    private var sinkClient: CMIOExtensionClient?
    private var lastSinkFrame = DispatchTime(uptimeNanoseconds: 0)
    private var placeholder: CVPixelBuffer?

    init(localizedName: String) {
        super.init()
        device = CMIOExtensionDevice(localizedName: localizedName, deviceID: deviceID, legacyDeviceID: nil, source: self)
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA,
                                       width: width, height: height, extensions: nil, formatDescriptionOut: &format)
        let attributes: NSDictionary = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes, &pool)
        let duration = CMTime(value: 1, timescale: Int32(frameRate))
        let streamFormat = CMIOExtensionStreamFormat(formatDescription: format, maxFrameDuration: duration,
                                                     minFrameDuration: duration, validFrameDurations: nil)
        source = CameraStreamSource(localizedName: "Ilusio.Video", streamID: sourceID, direction: .source,
                                    format: streamFormat, device: self)
        sink = CameraStreamSource(localizedName: "Ilusio.Sink", streamID: sinkID, direction: .sink,
                                  format: streamFormat, device: self)
        do {
            try device.addStream(source.stream)
            try device.addStream(sink.stream)
        } catch {
            fatalError("Falha ao criar os fluxos: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { props.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { props.model = "Ilusio Camera" }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: source (a chamada)

    func startSource() {
        queue.async { [self] in
            sourceClients += 1
            guard timer == nil else { return }
            // o relógio do quadro de espera: só manda placeholder quando o app não manda nada há 0,5 s
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate))
            t.setEventHandler { [weak self] in self?.sendPlaceholderIfIdle() }
            t.resume()
            timer = t
        }
    }

    func stopSource() {
        queue.async { [self] in
            sourceClients = max(0, sourceClients - 1)
            if sourceClients == 0 {
                timer?.cancel()
                timer = nil
            }
        }
    }

    private func sendPlaceholderIfIdle() {
        guard DispatchTime.now().uptimeNanoseconds - lastSinkFrame.uptimeNanoseconds > 500_000_000 else { return }
        if placeholder == nil { placeholder = makePlaceholder() }
        if let placeholder { send(placeholder) }
    }

    private func send(_ pixelBuffer: CVPixelBuffer) {
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true,
                                           makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
                                           sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        source.stream.send(sample, discontinuity: [],
                           hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
    }

    /// Quadro escuro com "Abra o Ilusio" no meio.
    private func makePlaceholder() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(width), height: Int(height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return buffer }
        ctx.setFillColor(CGColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: Int(width), height: Int(height)))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 44, nil)
        let text = NSAttributedString(string: "Abra o Ilusio", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.85),
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: (CGFloat(height) - bounds.height) / 2)
        CTLineDraw(line, ctx)
        return buffer
    }

    // MARK: sink (o app)

    func startSink(client: CMIOExtensionClient) {
        queue.async { [self] in
            sinkClient = client
            consume(client)
        }
    }

    func stopSink() {
        queue.async { [self] in sinkClient = nil }
    }

    /// Pega o próximo frame que o app enfileirou e repassa pra chamada; se encadeia até o app parar.
    private func consume(_ client: CMIOExtensionClient) {
        sink.stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, _, error in
            guard let self else { return }
            queue.async {
                guard self.sinkClient === client else { return }
                if let sample, let pixels = CMSampleBufferGetImageBuffer(sample) {
                    self.lastSinkFrame = .now()
                    if self.sourceClients > 0 { self.send(pixels) }
                    let now = CMClockGetTime(CMClockGetHostTimeClock())
                    self.sink.stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(
                        sequenceNumber: sequence, hostTimeInNanoseconds: UInt64(now.seconds * Double(NSEC_PER_SEC))))
                    self.consume(client)
                } else {
                    if let error { log.debug("sink sem frame: \(error.localizedDescription)") }
                    // nada na fila ainda: tenta de novo daqui a meio frame
                    self.queue.asyncAfter(deadline: .now() + 0.5 / Double(frameRate)) {
                        if self.sinkClient === client { self.consume(client) }
                    }
                }
            }
        }
    }
}

final class CameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private unowned let device: CameraDeviceSource
    private let direction: CMIOExtensionStream.Direction
    private var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, direction: CMIOExtensionStream.Direction,
         format: CMIOExtensionStreamFormat, device: CameraDeviceSource) {
        self.format = format
        self.device = device
        self.direction = direction
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: direction,
                                     clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var activeFormatIndex = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        direction == .sink
            ? [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize,
               .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
            : [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { props.frameDuration = CMTime(value: 1, timescale: Int32(frameRate)) }
        if properties.contains(.streamSinkBufferQueueSize) { props.sinkBufferQueueSize = 1 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { props.sinkBuffersRequiredForStartup = 1 }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex { activeFormatIndex = index }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        if direction == .sink {
            guard let client else { return }
            device.startSink(client: client)
        } else {
            device.startSource()
        }
    }

    func stopStream() throws {
        if direction == .sink { device.stopSink() } else { device.stopSource() }
    }
}

final class CameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: CameraDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = CameraDeviceSource(localizedName: cameraName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Falha ao criar a câmera: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { props.manufacturer = "Ilusio" }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
