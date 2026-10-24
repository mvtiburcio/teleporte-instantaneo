import SwiftUI

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case home = "Início"
        case devices = "Câmera e mic"
        var id: Self { self }
        var icon: String {
            switch self {
            case .home: "play.circle"
            case .devices: "camera"
            }
        }
    }

    @State private var section: Section? = .home

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch section ?? .home {
            case .home: HomeView()
            case .devices: DevicesView()
            }
        }
        .frame(minWidth: 900, minHeight: 620)
    }
}
