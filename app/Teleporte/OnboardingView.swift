import SwiftUI

/// Tour da primeira abertura: ilustração à esquerda, texto e passos à direita. Termina abrindo a Configuração.
struct OnboardingView: View {
    var finish: (_ openSetup: Bool) -> Void
    @State private var step = 0

    private struct Page {
        let title: String
        let text: String
        let symbol: String
        let colors: [Color]
    }

    private let pages = [
        Page(title: "Bem-vindo ao Teleporte",
             text: "Suma da videochamada com um gesto, com o som e o efeito do Teletransporte Instantâneo. Este tour leva um minuto.",
             symbol: "sparkles", colors: [.orange, .pink]),
        Page(title: "Como funciona",
             text: "O Teleporte usa a sua câmera, aplica o efeito e entrega uma câmera e um microfone virtuais. Na chamada (Meet, Zoom, Teams ou WhatsApp), você escolhe esses dois no lugar dos normais.",
             symbol: "video.badge.waveform", colors: [.blue, .purple]),
        Page(title: "O gesto",
             text: "Encoste o indicador e o médio na testa e segure meio segundo. Você some com o som do Goku; repita para voltar. Sem a mão livre? Use o atalho ⌃⌥T.",
             symbol: "hand.raised.fingers.spread.fill", colors: [.green, .teal]),
        Page(title: "Vamos preparar",
             text: "Um checklist guia você em uns 5 minutos: permissões, câmera e som virtuais, o fundo e um teste. Cada item fica verde sozinho quando estiver certo.",
             symbol: "checklist", colors: [.orange, .yellow]),
    ]

    var body: some View {
        let page = pages[step]
        HStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: page.colors.map { $0.opacity(0.55) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: page.symbol)
                    .font(.system(size: 120, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .symbolEffect(.bounce, value: step)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                Text("Passo \(step + 1) de \(pages.count)").font(.callout).foregroundStyle(.secondary)
                Text(page.title).font(.largeTitle.bold())
                Text(page.text).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pages.indices, id: \.self) { i in
                        Label(pages[i].title, systemImage: i < step ? "checkmark.circle.fill" : (i == step ? "circle.inset.filled" : "circle"))
                            .foregroundStyle(i <= step ? .primary : .secondary)
                            .fontWeight(i == step ? .semibold : .regular)
                    }
                }
                .padding(.top, 8)
                Spacer()
                HStack {
                    Button("Pular") { finish(false) }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    if step > 0 {
                        Button("Voltar") { step -= 1 }.buttonStyle(.glass)
                    }
                    Button(step == pages.count - 1 ? "Abrir o checklist" : "Continuar") {
                        if step == pages.count - 1 { finish(true) } else { step += 1 }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
            .padding(40)
            .frame(width: 460)
            .frame(maxHeight: .infinity)
        }
        .animation(.smooth, value: step)
    }
}
