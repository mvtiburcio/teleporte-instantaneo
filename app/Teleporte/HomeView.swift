import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            preview
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button(model.running ? "Desligar" : "Ligar teleporte", systemImage: model.running ? "stop.fill" : "sparkles") {
                        Task { await model.toggleRunning() }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    Button(bgLabel, systemImage: "photo") { model.send("capture_bg", ["delay_s": 5]) }
                        .buttonStyle(.glass)
                        .disabled(!model.running)
                    Button("Some / Volta", systemImage: "wand.and.rays") { model.send("toggle") }
                        .buttonStyle(.glass)
                        .disabled(!(model.state?.bgReady ?? false))
                }
                .controlSize(.large)
            }
            status
            if let err = model.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .navigationTitle("Início")
    }

    private var bgLabel: String {
        (model.state?.bgReady ?? false) ? "Regravar fundo" : "Gravar fundo"
    }

    private var countdown: Int? { model.state?.bgCountdown.map { Int($0.rounded(.up)) } }

    private var preview: some View {
        ZStack {
            if let img = model.preview {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .scaleEffect(x: -1, y: 1)  // espelhada, como num espelho; a chamada recebe sem espelhar
            } else {
                Text(model.running ? "Iniciando…" : "Ligue o teleporte para ver a prévia")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay { backgroundGuide }
        .animation(.smooth, value: countdown)
        .animation(.smooth, value: model.bgSaved)
    }

    /// Instrução da gravação do fundo em cima da prévia: legível de longe, porque a pessoa está saindo do quadro.
    @ViewBuilder private var backgroundGuide: some View {
        if let c = countdown {
            VStack(spacing: 8) {
                Text("\(c)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(countsDown: true))
                Text("Saia do quadro").font(.title.bold())
                Text("e da frente da luz, pra sua sombra não ficar no fundo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if model.bgSaved {
            Label("Fundo gravado. Pode voltar!", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .symbolRenderingMode(.multicolor)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .glassEffect(.regular, in: .capsule)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            pill("Motor", on: model.state != nil)
            pill("Fundo", on: model.state?.bgReady ?? false)
            pill("Gesto", on: model.state?.gesture ?? false)
            if let fps = model.state?.fps {
                Text("\(Int(fps)) fps").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func pill(_ title: String, on: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Circle().fill(on ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}
