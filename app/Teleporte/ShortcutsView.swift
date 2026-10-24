import Carbon.HIToolbox
import SwiftUI

/// Aba "Atalhos": uma combinação por ação, gravada clicando no campo e pressionando as teclas.
struct ShortcutsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) { KeyRecorder(action: action) }
                }
            } header: {
                Text("Atalhos")
            } footer: {
                Text("Funcionam em qualquer app, inclusive com a chamada em primeiro plano. Use ⌃ ou ⌘ na combinação; Esc cancela a gravação.")
            }
            Section {
                Button("Restaurar padrões", systemImage: "arrow.counterclockwise") { model.resetShortcuts() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Atalhos")
    }
}

/// Campo que grava a próxima combinação pressionada.
struct KeyRecorder: View {
    @Environment(AppModel.self) private var model
    let action: ShortcutAction
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Pressione a combinação…" : (model.shortcuts[action]?.description ?? "—"))
                    .font(.body.monospaced())
                    .frame(minWidth: 170)
            }
            .buttonStyle(.glass)
            .tint(recording ? .orange : nil)
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            } else if model.shortcutFailures.contains(action) {
                Text("Não registrado: outro app usa essa combinação.").font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == UInt16(kVK_Escape) {
                    stop()
                } else if let combo = KeyCombo(event: event) {
                    message = model.setShortcut(action, combo)
                    stop()
                } else {
                    message = "Use ⌃ ou ⌘ na combinação."
                }
            }
            return nil  // a tecla não vai pra outro lugar enquanto grava
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
