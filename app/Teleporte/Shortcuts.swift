import AppKit
import Carbon.HIToolbox

/// Combinação de teclas no formato do Carbon (keyCode + modificadores), com o texto da tecla para exibir.
struct KeyCombo: Codable, Hashable, CustomStringConvertible {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    var description: String {
        let symbols: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return symbols.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        let map: [(NSEvent.ModifierFlags, Int)] = [(.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
        return map.reduce(0) { flags.contains($1.0) ? $0 | UInt32($1.1) : $0 }
    }

    /// O macOS 15+ não entrega atalho global feito só com ⌥/⇧: exige ⌃ ou ⌘.
    static func isAllowed(modifiers: UInt32) -> Bool {
        modifiers & UInt32(controlKey | cmdKey) != 0
    }

    /// Combinação a partir de uma tecla pressionada; nil se não tiver ⌃ ou ⌘.
    init?(event: NSEvent) {
        let mods = Self.carbonModifiers(event.modifierFlags)
        guard Self.isAllowed(modifiers: mods), let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, key: chars.uppercased())
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case toggle, power, background, reappear
    var id: Self { self }

    var title: String {
        switch self {
        case .toggle: "Sumir / voltar"
        case .power: "Ligar / desligar o teleporte"
        case .background: "Gravar o fundo"
        case .reappear: "Reaparecer na hora (sem efeito)"
        }
    }

    var defaultCombo: KeyCombo {
        let ctrlOpt = UInt32(controlKey | optionKey)
        switch self {
        case .toggle: return KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: ctrlOpt, key: "T")
        case .power: return KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: ctrlOpt, key: "L")
        case .background: return KeyCombo(keyCode: UInt32(kVK_ANSI_B), modifiers: ctrlOpt, key: "B")
        case .reappear: return KeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: ctrlOpt, key: "R")
        }
    }

    /// Outra ação que já usa a combinação (a própria ação não conta).
    static func conflict(for action: ShortcutAction, with combo: KeyCombo, in all: [ShortcutAction: KeyCombo]) -> ShortcutAction? {
        all.first { $0.key != action && $0.value == combo }?.key
    }
}

/// Atalhos globais pelo Carbon: chegam ao app mesmo com a chamada em primeiro plano e não pedem Acessibilidade.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var installed = false

    /// Registra (ou troca) o atalho de um id; false se o sistema recusar (combinação já tomada por outro app).
    func register(id: UInt32, combo: KeyCombo, action: @escaping @MainActor () -> Void) -> Bool {
        install()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x544C_5054), id: id)  // "TLPT"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.handlers[id]?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
