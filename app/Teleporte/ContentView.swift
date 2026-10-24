import SwiftUI

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case home = "Início"
        case devices = "Câmera e mic"
        case setup = "Configuração"
        case shortcuts = "Atalhos"
        case settings = "Ajustes"
        var id: Self { self }
        var icon: String {
            switch self {
            case .home: "play.circle"
            case .devices: "camera"
            case .setup: "checklist"
            case .shortcuts: "keyboard"
            case .settings: "gearshape"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var section: Section? = .home
    @AppStorage("theme") private var theme: AppTheme = .system

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                if s == .setup, model.checks.doneCount < SetupItem.allCases.count {
                    Label(s.rawValue, systemImage: s.icon)
                        .badge(Text("\(model.checks.doneCount)/\(SetupItem.allCases.count)"))
                } else {
                    Label(s.rawValue, systemImage: s.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch section ?? .home {
            case .home: HomeView()
            case .devices: DevicesView()
            case .setup: SetupView { section = .home }
            case .shortcuts: ShortcutsView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: theme, initial: true) { NSApp.appearance = theme.appearance }
    }
}
