import AVFoundation
import Observation
import SwiftUI

/// Estado do app: liga câmera + motor, repassa comandos e mantém a prévia (slot out a 15 fps).
@MainActor @Observable
final class AppModel {
    static let width = 1280, height = 720
    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Ilusio")
    static let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Ilusio/engine.log")

    var running = false
    var state: EngineEvent?
    var preview: CGImage?
    var lastError: String?
    var bgSaved = false  // confirmação "fundo gravado" por alguns segundos
    var micLevel = 0.0

    // checklist da Configuração; fundo, gesto e app de chamada ficam guardados depois da primeira vez
    var checks = SetupChecks()
    var callAppDone: Bool {
        didSet { UserDefaults.standard.set(callAppDone, forKey: "setup.callApp"); refreshChecks() }
    }
    @ObservationIgnored private var backgroundDone = UserDefaults.standard.bool(forKey: "setup.bg")
    @ObservationIgnored private var gestureDone = UserDefaults.standard.bool(forKey: "setup.gesture")

    // dispositivos e ajustes, lembrados entre aberturas do app
    var cameras: [Devices.Item] = []
    var microphones: [Devices.Item] = []
    var cameraID: String?  // câmera em uso: a preferida se estiver conectada, senão a do Mac
    var preferredCameraID: String? { didSet { UserDefaults.standard.set(preferredCameraID, forKey: "cameraID") } }
    var micName: String? { didSet { UserDefaults.standard.set(micName, forKey: "micName") } }
    /// Com o Ilusio ligado, o Ilusio Mic vira o microfone do sistema (pro WhatsApp, que esconde microfones virtuais).
    var micAsSystem: Bool {
        didSet {
            UserDefaults.standard.set(micAsSystem, forKey: "micAsSystem")
            guard running else { return }  // ligado: vale na hora
            if micAsSystem { SystemAudio.takeDefaultInput() } else { SystemAudio.restoreDefaultInput() }
        }
    }
    var gain: Double {
        didSet { UserDefaults.standard.set(gain, forKey: "gain"); send("set", ["gain": gain]) }
    }
    var fps: Int {
        didSet {
            UserDefaults.standard.set(fps, forKey: "fps")
            applyFPS()
        }
    }
    /// Até quanto a câmera escolhida chega na fps pedida (pode ser menos): calculado dos formatos, ligado ou não.
    var cameraFPS: Double? { cameraID.flatMap { CameraCapture.maxFPS(deviceID: $0, wanted: Double(fps)) } }
    var reach: Double {
        didSet { UserDefaults.standard.set(reach, forKey: "reach"); send("set", ["reach": reach]) }
    }

    // atalhos globais
    var shortcuts: [ShortcutAction: KeyCombo] = [:]
    var shortcutFailures: Set<ShortcutAction> = []  // o sistema recusou (outro app usa a combinação)

    @ObservationIgnored private var engine: EngineClient?
    @ObservationIgnored private var capture: CameraCapture?
    @ObservationIgnored private var frames: FrameBuffer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var cameraFeed: CameraFeed?
    // sem isto, o App Nap freia o envio de frames quando a chamada (WhatsApp) cobre a janela: o vídeo trava
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var activation: CameraActivation?
    var cameraMessage: String?  // retorno da ativação da câmera do Ilusio
    var micMessage: String?  // retorno da instalação do microfone do Ilusio
    var installingMic = false
    @ObservationIgnored private var lastOut: UInt64 = 0
    @ObservationIgnored private var outBytes = [UInt8](repeating: 0, count: width * height * 4)

    init() {
        let d = UserDefaults.standard
        callAppDone = d.bool(forKey: "setup.callApp")
        micAsSystem = d.object(forKey: "micAsSystem") as? Bool ?? true
        SystemAudio.restoreDefaultInput()  // o app pode ter fechado à força com o Ilusio Mic como padrão
        gain = d.object(forKey: "gain") as? Double ?? 0.8
        reach = d.object(forKey: "reach") as? Double ?? 1.5
        fps = d.object(forKey: "fps") as? Int ?? 30
        micName = d.string(forKey: "micName")
        preferredCameraID = d.string(forKey: "cameraID")
        refreshDevices()
        for action in ShortcutAction.allCases {
            let saved = d.data(forKey: "hotkey.\(action.rawValue)").flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
            shortcuts[action] = saved ?? action.defaultCombo
            registerShortcut(action)
        }
        refreshChecks()
        // app atualizado: o macOS só troca a extensão quando o app pede (mesma versão = nada acontece)
        if VirtualCamera.isInstalled { activateCamera(quiet: true) }
        if Bundle.main.bundlePath.hasPrefix("/Applications/") { EngineClient.warmUp() }  // só no app instalado  // só a Ilusio Camera: com só o OBS, não pede nada
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in  // permissão dada em Ajustes, câmera aprovada...
            MainActor.assumeIsolated { self?.refreshChecks() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshChecks() }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.devicesChanged() }
            }
        }
    }

    func refreshChecks() {
        let now = SetupChecks.current(background: backgroundDone, gesture: gestureDone, callApp: callAppDone)
        if now != checks { checks = now }
    }

    private func markDone(_ key: String) {
        UserDefaults.standard.set(true, forKey: key)
        if key == "setup.bg" { backgroundDone = true } else { gestureDone = true }
        refreshChecks()
    }

    private func refreshDevices() {
        cameras = Devices.cameras()
        microphones = Devices.microphones()
        cameraID = Devices.pick(cameras, saved: preferredCameraID)?.id  // nunca sobrescreve a preferência
    }

    /// Câmera ou microfone conectado/desconectado (iPhone que acorda, webcam USB...).
    private func devicesChanged() {
        let using = cameraID
        refreshDevices()
        refreshChecks()  // microfone ou câmera do Ilusio acabaram de aparecer
        guard running, let cameraID, cameraID != using else { return }
        if cameraID != preferredCameraID {
            lastError = "A câmera em uso foi desconectada; usando \(cameras.first { $0.id == cameraID }?.name ?? "outra câmera")."
        }
        switchCapture(to: cameraID)  // caiu pra outra, ou a preferida voltou
    }

    /// Escolha da pessoa: vira a preferência e, com o Ilusio ligado, troca ao vivo sem reiniciar o motor.
    func selectCamera(_ id: String) {
        preferredCameraID = id
        cameraID = id
        if running { switchCapture(to: id) }
    }

    private func switchCapture(to id: String) {
        do { try capture?.start(deviceID: id, fps: Double(fps)) } catch { lastError = error.localizedDescription }
    }

    private func applyFPS() {
        guard running, let cameraID else { return }
        switchCapture(to: cameraID)  // a câmera virtual e o motor seguem a velocidade dos frames
    }

    /// Troca o microfone; o motor abre o microfone ao iniciar, então religa se estiver ligado.
    func selectMic(_ name: String?) async {
        micName = name
        guard running else { return }
        stop()
        await start()
    }

    private func registerShortcut(_ action: ShortcutAction) {
        guard let combo = shortcuts[action], let index = ShortcutAction.allCases.firstIndex(of: action) else { return }
        let ok = HotKeyCenter.shared.register(id: UInt32(index + 1), combo: combo) { [weak self] in self?.perform(action) }
        if ok { shortcutFailures.remove(action) } else { shortcutFailures.insert(action) }
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .toggle: send("toggle")
        case .power: Task { await toggleRunning() }
        case .background: send("capture_bg", ["delay_s": 5])
        case .reappear: send("reappear")
        }
    }

    /// Troca o atalho de uma ação; devolve o motivo se não deu (e mantém o anterior).
    func setShortcut(_ action: ShortcutAction, _ combo: KeyCombo) -> String? {
        if let other = ShortcutAction.conflict(for: action, with: combo, in: shortcuts) {
            return "Já usado em “\(other.title)”."
        }
        let previous = shortcuts[action]
        shortcuts[action] = combo
        registerShortcut(action)
        if shortcutFailures.contains(action) {
            shortcuts[action] = previous
            registerShortcut(action)
            return "Outro app já usa \(combo)."
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: "hotkey.\(action.rawValue)")
        return nil
    }

    /// Durante a gravação de um atalho: o Carbon consome as combinações registradas antes da janela,
    /// então sem isso apertar um atalho existente executaria a ação em vez de ser gravado.
    func suspendShortcuts() {
        for index in ShortcutAction.allCases.indices { HotKeyCenter.shared.unregister(id: UInt32(index + 1)) }
    }

    func resumeShortcuts() {
        ShortcutAction.allCases.forEach(registerShortcut)
    }

    func resetShortcuts() {
        for action in ShortcutAction.allCases {
            UserDefaults.standard.removeObject(forKey: "hotkey.\(action.rawValue)")
            shortcuts[action] = action.defaultCombo
            registerShortcut(action)
        }
    }

    /// Instala/atualiza a "Ilusio Camera"; a pessoa aprova uma vez em Ajustes do Sistema.
    /// `quiet`: na abertura do app, só pra trocar a câmera instalada pela desta versão; o sucesso não aparece.
    func activateCamera(quiet: Bool = false) {
        guard VirtualCamera.appIsInApplications else {
            if !quiet { cameraMessage = "Mova o Ilusio para a pasta Aplicativos e abra de novo: o macOS só ativa a câmera de lá." }
            return
        }
        // um pedido por vez: um novo substituiria o anterior e os retornos dele se perderiam
        guard activation == nil else {
            // pedido pendente: o botão leva de novo aos Ajustes em vez de pedir outra vez
            if !quiet { NSWorkspace.shared.open(VirtualCamera.approvalSettingsURL) }
            return
        }
        let activation = CameraActivation(opensSettings: !quiet) { [weak self] text in
            if !(quiet && text == CameraActivation.doneText) { self?.cameraMessage = text }
            if text != CameraActivation.approvalText { self?.activation = nil }  // terminou (sucesso, erro ou reinício)
            self?.refreshChecks()
        }
        self.activation = activation
        activation.submit()
    }

    /// Instala o "Ilusio Mic" (pede a senha de administrador uma vez).
    func installMic() async {
        guard !installingMic else { return }  // clique repetido pediria a senha de novo
        installingMic = true
        defer { installingMic = false }
        let result = await Task.detached { VirtualMic.install() }.value
        guard result == VirtualMic.doneText else {
            micMessage = result
            return
        }
        // o coreaudiod leva alguns segundos pra reiniciar e anunciar o "Ilusio Mic": espera em vez de
        // conferir uma vez só (antes, parecia que não tinha instalado e a pessoa clicava de novo)
        micMessage = "Ativando o microfone…"
        for _ in 0..<30 where !checks.virtualAudio {
            try? await Task.sleep(for: .milliseconds(500))
            refreshChecks()
        }
        micMessage = checks.virtualAudio ? result : "Instalado, mas o macOS ainda não mostrou o microfone. Se em 1 minuto não aparecer, reinicie o Mac."
    }

    func toggleRunning() async {
        if running { stop() } else { await start() }
    }

    func start() async {
        lastError = nil
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            lastError = "Sem permissão de câmera: libere em Ajustes > Privacidade e Segurança > Câmera."
            return
        }
        refreshDevices()
        guard let id = cameraID else {
            lastError = "Nenhuma câmera encontrada."
            return
        }
        guard let (exe, args) = EngineClient.command() else {
            lastError = "Motor não encontrado: rode ./setup.sh no repositório."
            return
        }
        var started: CameraCapture?  // pra desligar a câmera e o feed se o motor não subir
        var feed: CameraFeed?
        do {
            try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
            let shm = Self.supportDir.appendingPathComponent("frames.shm").path
            let frames = try FrameBuffer(path: shm, width: Self.width, height: Self.height)
            let capture = CameraCapture(buffer: frames)
            try capture.start(deviceID: id, fps: Double(fps))
            started = capture
            // com a câmera própria, o app entrega o vídeo; o OBS só vale rodando do código (o app instalado
            // caía nele quando a câmera ainda não estava pronta e mostrava o erro do OBS)
            feed = CameraFeed(frames: frames)
            if feed == nil && VirtualCamera.appIsInApplications {
                throw CameraNotReady()
            }
            let engine = EngineClient()
            let current = ObjectIdentifier(engine)
            engine.onEvent = { [weak self] in self?.handle($0) }
            engine.onExit = { [weak self] code in
                guard let self, let e = self.engine, ObjectIdentifier(e) == current else { return }  // motor antigo saindo
                stop()
                lastError = "O motor parou (código \(code)). Detalhes em \(Self.logURL.path)."
            }
            try engine.start(executable: exe, arguments: args, log: Self.logURL)
            var fields: [String: Any] = ["shm": shm, "gain": gain, "reach": reach, "vcam": feed == nil, "fps": fps]
            // o microfone de verdade é decidido antes de o Ilusio Mic virar o padrão do sistema
            if let mic = SystemAudio.engineMic(chosen: micName, systemDefault: SystemAudio.defaultInputName) { fields["mic"] = mic }
            engine.send("start", fields)
            if micAsSystem { SystemAudio.takeDefaultInput() }  // WhatsApp: "Usar a configuração do sistema"
            (self.frames, self.capture, self.engine, self.cameraFeed, cameraID) = (frames, capture, engine, feed, id)
            running = true
            activity = activity ?? ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                                         reason: "Ilusio ligado: entregando vídeo à chamada")
            lastOut = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPreview() }
            }
        } catch {
            started?.stop()
            feed?.stop()
            lastError = error.localizedDescription
        }
    }

    func stop() {
        SystemAudio.restoreDefaultInput()
        timer?.invalidate()
        engine?.stop()
        capture?.stop()
        cameraFeed?.stop()
        (timer, engine, capture, frames, cameraFeed) = (nil, nil, nil, nil, nil)
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        running = false
        micLevel = 0
        state = nil
        preview = nil
    }

    func send(_ cmd: String, _ fields: [String: Any] = [:]) {
        engine?.send(cmd, fields)
    }

    private func handle(_ ev: EngineEvent) {
        switch ev.event {
        case "state":
            if ev.bgReady == true, state?.bgCountdown != nil { flashBgSaved() }  // a contagem acabou de gravar o fundo
            if ev.bgReady == true, !backgroundDone { markDone("setup.bg") }
            state = ev
        case "mic_level": micLevel = ev.rms ?? 0
        case "gesture_seen": if !gestureDone { markDone("setup.gesture") }
        case "error": lastError = ev.msg ?? ev.code
        default: break
        }
    }

    private func flashBgSaved() {
        bgSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            bgSaved = false
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

/// A "Ilusio Camera" não abriu (aprovação pendente ou a câmera nova ainda carregando depois de atualizar).
struct CameraNotReady: LocalizedError {
    var errorDescription: String? {
        "A câmera do Ilusio ainda não está pronta. Veja o item Câmera virtual em Configuração (se acabou de atualizar, reinicie o Mac)."
    }
}
