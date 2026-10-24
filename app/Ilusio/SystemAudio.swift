import CoreAudio
import Foundation

/// Microfone padrão do macOS. O WhatsApp (e outros apps) escondem microfones "virtuais" da lista, então, com o
/// Ilusio ligado, o padrão do sistema vira o Ilusio Mic ("Usar a configuração do sistema" funciona) e volta
/// para o anterior ao desligar.
enum SystemAudio {
    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static let previousKey = "previousInputUID"

    /// Microfone de verdade que o motor deve abrir: o escolhido; senão o padrão do sistema, se não for virtual.
    static func engineMic(chosen: String?, systemDefault: String?) -> String? {
        if let chosen { return chosen }
        guard let systemDefault, !Devices.isVirtual(systemDefault) else { return nil }
        return systemDefault
    }

    static var defaultInputName: String? { defaultInput.flatMap { string($0, kAudioObjectPropertyName) } }

    /// Põe o Ilusio Mic como microfone do sistema, guardando o anterior pra devolver depois.
    static func takeDefaultInput() {
        guard let ilusio = input(named: VirtualMic.deviceName), let current = defaultInput, current != ilusio else { return }
        if let uid = string(current, kAudioDevicePropertyDeviceUID) {
            UserDefaults.standard.set(uid, forKey: previousKey)
        }
        setDefaultInput(ilusio)
    }

    /// Devolve o microfone anterior, se o padrão ainda for o Ilusio Mic (a pessoa pode ter trocado na mão).
    static func restoreDefaultInput() {
        guard let uid = UserDefaults.standard.string(forKey: previousKey) else { return }
        defer { UserDefaults.standard.removeObject(forKey: previousKey) }
        guard let ilusio = input(named: VirtualMic.deviceName), defaultInput == ilusio,
              let previous = devices().first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }) else { return }
        setDefaultInput(previous)
    }

    // MARK: CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func devices() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func input(named name: String) -> AudioDeviceID? {
        devices().first { hasInput($0) && string($0, kAudioObjectPropertyName) == name }
    }

    private static var defaultInput: AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private static func setDefaultInput(_ id: AudioDeviceID) {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }
}
