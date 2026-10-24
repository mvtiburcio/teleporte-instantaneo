import AVFoundation
import CoreAudio

/// Câmeras e microfones reais: os virtuais (do próprio Teleporte, do OBS e do BlackHole) nunca são fonte.
enum Devices {
    static let virtualNames = ["OBS Virtual Camera", "Teleporte Camera", "BlackHole", "Teleporte Mic"]

    struct Item: Identifiable, Hashable {
        let id: String
        let name: String
        let builtIn: Bool
    }

    static func isVirtual(_ name: String) -> Bool {
        virtualNames.contains { name.contains($0) }
    }

    static func cameras() -> [Item] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
            .devices.filter { !isVirtual($0.localizedName) }
            .map { Item(id: $0.uniqueID, name: $0.localizedName, builtIn: $0.deviceType == .builtInWideAngleCamera) }
    }

    static func microphones() -> [Item] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.filter { !isVirtual($0.localizedName) }
            .map { Item(id: $0.uniqueID, name: $0.localizedName,
                        builtIn: $0.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn)) }
    }

    /// A escolha salva, se ainda estiver conectada; senão a embutida do Mac (o iPhone por Continuidade
    /// só é usado se a pessoa escolher); senão a primeira.
    static func pick(_ items: [Item], saved: String?) -> Item? {
        items.first { $0.id == saved } ?? items.first { $0.builtIn } ?? items.first
    }
}
