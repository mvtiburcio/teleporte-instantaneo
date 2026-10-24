import SwiftUI

/// Aba "Câmera e mic": qual câmera e microfone usar, teste de som e ajustes finos do efeito.
struct DevicesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Câmera", selection: Binding(get: { model.cameraID ?? "" }, set: { model.selectCamera($0) })) {
                    ForEach(model.cameras) { Text($0.name).tag($0.id) }
                }
            } header: {
                Text("Câmera")
            } footer: {
                Text("A câmera do iPhone (Continuidade) e as webcams USB aparecem aqui, mas só são usadas se você escolher.")
            }

            Section {
                Picker("Microfone", selection: Binding(get: { model.micName ?? "" },
                                                       set: { name in Task { await model.selectMic(name.isEmpty ? nil : name) } })) {
                    Text("Padrão do sistema").tag("")
                    ForEach(model.microphones) { Text($0.name).tag($0.name) }
                    if let saved = model.micName, !model.microphones.contains(where: { $0.name == saved }) {
                        Text("\(saved) (desconectado)").tag(saved)  // o motor usa o padrão até ele voltar
                    }
                }
                LabeledContent("Nível") {
                    if model.running {
                        ProgressView(value: min(model.micLevel.squareRoot() * 2.5, 1))  // raiz: a fala aparece na barra
                            .tint(.green)
                            .frame(maxWidth: 220)
                    } else {
                        Text("Ligue o Ilusio para ver").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Som do efeito") {
                    Button("Testar", systemImage: "speaker.wave.2.fill") { model.send("test_sound") }
                        .disabled(!model.running)
                }
            } header: {
                Text("Microfone")
            } footer: {
                Text("O Ilusio mistura este microfone com o som do efeito. Na chamada, escolha o microfone virtual “Ilusio Mic”.")
            }

            Section {
                Picker("Taxa de quadros", selection: $model.fps) {
                    ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Vídeo")
            } footer: {
                if let delivered = model.cameraFPS, delivered < Double(model.fps) {
                    Text("Esta câmera vai até \(Int(delivered)) fps; o Ilusio usa esse máximo.")
                } else {
                    Text("60 fps deixa o movimento mais fluido e usa mais processador. 30 fps é o padrão das chamadas.")
                }
            }

            Section("Ajustes finos") {
                LabeledContent("Volume do efeito") {
                    Slider(value: $model.gain, in: 0...1.5) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .frame(maxWidth: 260)
                }
                LabeledContent("Sensibilidade do gesto") {
                    Slider(value: $model.reach, in: 1.0...2.5) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Exigente")
                    } maximumValueLabel: {
                        Text("Fácil")
                    }
                    .frame(maxWidth: 260)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Câmera e mic")
    }
}
