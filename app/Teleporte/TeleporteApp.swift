import SwiftUI

@main
struct TeleporteApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        signal(SIGPIPE, SIG_IGN)  // escrever pra um motor que morreu não pode derrubar o app
    }

    var body: some Scene {
        WindowGroup("Teleporte") {
            ContentView()
                .environment(model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1040, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.stop() }  // o motor também sai sozinho quando o stdin fecha
    }
}
