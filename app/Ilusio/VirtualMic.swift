import Foundation

/// Microfone virtual próprio ("Ilusio Mic"): driver de áudio (BlackHole, GPL-3, compilado com o nome do Ilusio)
/// que vai dentro do app e é instalado em /Library/Audio/Plug-Ins/HAL com a senha de administrador, uma vez.
enum VirtualMic {
    static let deviceName = "Ilusio Mic"
    static let doneText = "Microfone do Ilusio instalado. O áudio do Mac pode ter cortado por 2 segundos."
    static let installedPath = "/Library/Audio/Plug-Ins/HAL/IlusioMic.driver"

    static var bundled: URL? { Bundle.main.url(forResource: "IlusioMic", withExtension: "driver") }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedPath) }

    /// O driver instalado é de outra versão que o que veio dentro deste app (o app foi atualizado).
    static var needsUpdate: Bool {
        needsUpdate(installed: Bundle(path: installedPath)?.infoDictionary?["CFBundleVersion"] as? String,
                    bundled: bundled.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleVersion"] as? String })
    }

    static func needsUpdate(installed: String?, bundled: String?) -> Bool {
        guard let installed, let bundled else { return false }  // sem driver instalado é "instalar", não "atualizar"
        return installed != bundled
    }

    /// AppleScript que copia o driver e reinicia o áudio do Mac. Falha na cópia é erro; falha só no reinício, não.
    /// O caminho de origem entra só como string escapada e passa por `quoted form of`, então não dá pra injetar comando pelo nome da pasta.
    static func installScript(source: String) -> String {
        let escaped = source.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        set src to "\(escaped)"
        set dst to "\(installedPath)"
        do shell script "rm -rf " & quoted form of dst & " && ditto " & quoted form of src & " " & quoted form of dst & ¬
            " && chown -R root:wheel " & quoted form of dst & " && (killall coreaudiod || true)" with administrator privileges
        """
    }

    /// Pede a senha e instala; devolve a mensagem pra mostrar no checklist. Bloqueia: chamar fora da main.
    static func install() -> String {
        guard let source = bundled else { return "O microfone não veio dentro deste app. Baixe a versão completa do Ilusio." }
        var error: NSDictionary?
        NSAppleScript(source: installScript(source: source.path))?.executeAndReturnError(&error)
        if let error {
            // -128: a pessoa cancelou o pedido de senha
            return (error[NSAppleScript.errorNumber] as? Int) == -128
                ? "Instalação cancelada."
                : "Não deu pra instalar o microfone: \(error[NSAppleScript.errorMessage] as? String ?? "erro desconhecido")."
        }
        return doneText
    }
}
