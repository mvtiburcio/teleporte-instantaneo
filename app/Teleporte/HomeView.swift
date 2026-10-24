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
        .overlay { gestureGlow }
        .overlay(alignment: .topLeading) { statusChips.padding(14) }
        .overlay(alignment: .topTrailing) { fps.padding(14) }
        .overlay(alignment: .bottomLeading) { CameraMenu().padding(14) }
        .overlay { backgroundGuide }
        .animation(.smooth, value: countdown)
        .animation(.smooth, value: model.bgSaved)
        .animation(.smooth(duration: 0.25), value: gesture)
    }

    private var gesture: Bool { model.state?.gesture ?? false }

    /// Borda verde enquanto o gesto está sendo reconhecido: mostra que é só segurar.
    private var gestureGlow: some View {
        RoundedRectangle(cornerRadius: 22)
            .strokeBorder(Color.green, lineWidth: 3)
            .shadow(color: .green.opacity(0.8), radius: 14)
            .opacity(gesture ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var statusChips: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                chip(model.state != nil ? "Ao vivo" : "Desligado", on: model.state != nil)
                if model.state != nil {
                    chip((model.state?.bgReady ?? false) ? "Fundo pronto" : "Sem fundo", on: model.state?.bgReady ?? false)
                }
            }
        }
    }

    @ViewBuilder private var fps: some View {
        if let fps = model.state?.fps {
            Text("\(Int(fps)) fps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private func chip(_ title: String, on: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(on ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
                .shadow(color: on ? .green : .clear, radius: 4)
            Text(title)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
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
}

/// Seletor de câmera sobre a prévia: troca ao vivo, sem desligar o teleporte.
struct CameraMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.cameras) { c in
                Button {
                    model.selectCamera(c.id)
                } label: {
                    if c.id == model.cameraID { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                }
            }
        } label: {
            Label(model.cameras.first { $0.id == model.cameraID }?.name ?? "Escolher câmera", systemImage: "camera.fill")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
    }
}
