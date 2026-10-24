import AVFoundation

/// Itens do checklist da Configuração, na ordem em que a pessoa resolve.
enum SetupItem: Int, CaseIterable, Identifiable {
    case camera, mic, virtualCamera, virtualAudio, background, gesture, callApp
    var id: Self { self }
}

/// O que já está pronto. Os itens de sistema se conferem sozinhos; fundo e gesto vêm do motor e ficam guardados;
/// o app de chamada é marcado à mão.
struct SetupChecks: Equatable {
    var camera = false
    var mic = false
    var virtualCamera = false
    var virtualAudio = false
    var background = false
    var gesture = false
    var callApp = false

    // só os dispositivos do próprio Ilusio contam: com OBS/BlackHole já instalados, o checklist ficava verde e
    // nunca oferecia ativar a Ilusio Camera nem instalar o Ilusio Mic (e no WhatsApp a OBS Virtual Camera congela)
    static let virtualCameraNames = ["Ilusio Camera"]
    static let virtualAudioNames = ["Ilusio Mic"]

    static func hasOwn(_ deviceNames: [String], _ ownNames: [String]) -> Bool {
        deviceNames.contains { name in ownNames.contains { name.contains($0) } }
    }

    static func current(background: Bool, gesture: Bool, callApp: Bool) -> SetupChecks {
        let video = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified)
            .devices.map(\.localizedName)
        let audio = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map(\.localizedName)
        return SetupChecks(
            camera: AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            mic: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            virtualCamera: hasOwn(video, virtualCameraNames),
            // driver do Ilusio desatualizado volta a pendente, pra pessoa atualizar (pede senha)
            virtualAudio: hasOwn(audio, virtualAudioNames) && !VirtualMic.needsUpdate,
            background: background, gesture: gesture, callApp: callApp)
    }

    func isDone(_ item: SetupItem) -> Bool {
        switch item {
        case .camera: camera
        case .mic: mic
        case .virtualCamera: virtualCamera  // só o dispositivo conta: extensão instalada mas não aprovada não basta
        case .virtualAudio: virtualAudio
        case .background: background
        case .gesture: gesture
        case .callApp: callApp
        }
    }

    var doneCount: Int { SetupItem.allCases.filter(isDone).count }
    var firstPending: SetupItem? { SetupItem.allCases.first { !isDone($0) } }
}
