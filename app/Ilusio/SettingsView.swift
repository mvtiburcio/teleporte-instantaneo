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
    @AppStorage(OnboardingView.doneKey) private var onboarded = false
    @Environment(AppModel.self) private var model
    @State private var reportMessage: String?

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
                LabeledContent("Relatório pro suporte") {
                    Button("Gerar relatório", systemImage: "doc.text") { reportMessage = Report.save(model: model) }
                }
                LabeledContent("Registro do motor") {
                    Button("Mostrar no Finder", systemImage: "folder") { showLog() }
                }
                LabeledContent("Atualizações") {
                    Button("Buscar atualizações", systemImage: "arrow.down.circle") { IlusioApp.updater.checkForUpdates(nil) }
                }
                LabeledContent("Versão", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            } header: {
                Text("Suporte")
            } footer: {
                Text(reportMessage ?? "Se algo der errado, gere o relatório e mande pra gente: ele leva o motivo, sem precisar do Terminal.")
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
