import Sparkle
import SwiftUI

@main
struct IlusioApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    /// Procura atualização sozinho (1x por dia) e pelo menu; baixa, troca o app no lugar e reabre.
    static let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        signal(SIGPIPE, SIG_IGN)  // escrever pra um motor que morreu não pode derrubar o app
    }

    var body: some Scene {
        WindowGroup("Ilusio") {
            ContentView()
                .environment(model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1040, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Buscar atualizações…") { Self.updater.checkForUpdates(nil) }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.stop() }  // o motor também sai sozinho quando o stdin fecha
    }
}
