import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }

    /// nil = acompanha o sistema; aplicado em NSApp.appearance, que volta pro sistema sem reiniciar.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Aba "Ajustes": tema do app e ajuda pra suporte.
struct SettingsView: View {
    @AppStorage("theme") private var theme: AppTheme = .system
    @AppStorage("onboarded") private var onboarded = true

    var body: some View {
        Form {
            Section("Aparência") {
                Picker("Tema", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Ajuda") {
                LabeledContent("Tour de boas-vindas") {
                    Button("Rever o tour", systemImage: "play.rectangle") { onboarded = false }
                }
            }
            Section {
                LabeledContent("Registro do motor") {
                    Button("Mostrar no Finder", systemImage: "folder") { showLog() }
                }
                LabeledContent("Versão", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            } header: {
                Text("Suporte")
            } footer: {
                Text("Se algo der errado, o registro do motor mostra o motivo.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
    }

    private func showLog() {
        let log = AppModel.logURL
        if FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log])
        } else {
            try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            NSWorkspace.shared.open(log.deletingLastPathComponent())
        }
    }
}
