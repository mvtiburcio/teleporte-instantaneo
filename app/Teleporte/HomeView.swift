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
        if let c = model.state?.bgCountdown { return "Fundo em \(Int(c.rounded(.up))) s" }
        return (model.state?.bgReady ?? false) ? "Regravar fundo" : "Gravar fundo"
    }

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
