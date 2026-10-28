import AVFoundation
import SwiftUI

/// Aba "Configuração": checklist guiado até o efeito funcionar na chamada. Cada item se confere sozinho
/// (menos o do app de chamada) e o primeiro pendente abre com o passo a passo e o botão que resolve.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    var goHome: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(SetupItem.allCases) { item in
                    SetupRow(item: item, expanded: item == model.checks.firstPending, goHome: goHome)
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Configuração")
        .animation(.smooth, value: model.checks)
    }

    private var header: some View {
        let done = model.checks.doneCount, total = SetupItem.allCases.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(done == total ? "Tudo pronto! 🎉" : "Vamos deixar tudo pronto")
                .font(.largeTitle.bold())
            Text(done == total ? "Na chamada, faça o gesto e suma." : "\(done) de \(total) · uns 5 minutos. Cada item fica verde sozinho quando estiver certo.")
                .foregroundStyle(.secondary)
            ProgressView(value: Double(done), total: Double(total)).tint(.orange)
        }
        .padding(.bottom, 6)
    }
}

private struct SetupRow: View {
    @Environment(AppModel.self) private var model
    let item: SetupItem
    let expanded: Bool
    var goHome: () -> Void
    @State private var callApp = CallApp.meet

    private var done: Bool { model.checks.isDone(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? Color.green : Color.clear)
                    Circle().strokeBorder(done ? Color.clear : Color.secondary, lineWidth: 2)
                    if done {
                        Image(systemName: "checkmark").font(.callout.bold()).foregroundStyle(.white)
                    } else {
                        Text("\(item.rawValue + 1)").font(.callout.bold())
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(done ? doneText : subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if !done, let (label, run) = action {
                    if expanded {
                        Button(label, action: run).buttonStyle(.glassProminent).tint(.orange)
                    } else {
                        Button(label, action: run).buttonStyle(.glass)
                    }
                }
            }
            if expanded && !done { guide.padding(.leading, 42) }
        }
        .padding(16)
        .glassEffect(expanded && !done ? .regular.tint(.orange.opacity(0.12)) : .regular, in: .rect(cornerRadius: 18))
    }

    // MARK: textos

    private var title: String {
        switch item {
        case .camera: "Permitir a câmera"
        case .mic: "Permitir o microfone"
        case .virtualCamera: "Câmera virtual"
        case .virtualAudio: "Som virtual"
        case .background: "Gravar o fundo"
        case .gesture: "Testar o gesto"
        case .callApp: "Escolher no app de chamada"
        }
    }

    private var subtitle: String {
        switch item {
        case .camera: "Para ver você e reconhecer o gesto."
        case .mic: "Para misturar a sua voz com o som do efeito."
        case .virtualCamera:
            // a antiga carregada e sem aprovação pendente: só o reinício troca (macOS segura a extensão em uso)
            VirtualCamera.isInstalled && model.cameraMessage != CameraActivation.approvalText
                ? "A câmera nova foi ativada, mas o Mac ainda usa a antiga: reinicie o Mac."
                : model.cameraMessage ?? "A “Ilusio Camera” entrega o vídeo com o efeito pra chamada."
        case .virtualAudio: model.micMessage ?? "O “Ilusio Mic” entrega a sua voz + o som do efeito pra chamada."
        case .background: "A imagem que aparece quando você some."
        case .gesture: "Dois dedos na testa até ouvir o som."
        case .callApp: "Câmera “Ilusio Camera” e microfone “Ilusio Mic”."
        }
    }

    private var doneText: String {
        switch item {
        case .camera, .mic: "Liberado."
        case .virtualCamera: "Câmera virtual encontrada."
        case .virtualAudio: "Som virtual encontrado."
        case .background: "Fundo gravado (dá pra regravar no Início)."
        case .gesture: "Gesto reconhecido."
        case .callApp: "Feito."
        }
    }

    // MARK: botão que resolve

    private var action: (String, () -> Void)? {
        switch item {
        case .camera: permissionAction(.video, pane: "Privacy_Camera")
        case .mic: permissionAction(.audio, pane: "Privacy_Microphone")
        case .virtualCamera:
            VirtualCamera.appIsInApplications
                ? (model.cameraMessage == CameraActivation.approvalText ? "Abrir Ajustes" : "Ativar a câmera", { model.activateCamera() })
                : ("Mostrar no Finder", { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) })
        case .virtualAudio:
            (model.installingMic ? "Instalando…" : (VirtualMic.isInstalled ? "Atualizar o microfone" : "Instalar o microfone"),
             { Task { await model.installMic() } })
        case .background, .gesture: ("Ir para o Início", goHome)
        case .callApp: ("Já escolhi", { model.callAppDone = true })
        }
    }

    private func permissionAction(_ media: AVMediaType, pane: String) -> (String, () -> Void) {
        if AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
            return ("Permitir", { AVCaptureDevice.requestAccess(for: media) { _ in } })
        }
        // negada antes: só os Ajustes do Sistema mudam
        return ("Abrir Ajustes", {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        })
    }

    // MARK: passo a passo do item atual

    @ViewBuilder private var guide: some View {
        switch item {
        case .camera, .mic:
            steps(["Clique em Permitir e confirme no aviso do macOS.",
                   "Se você negou antes, o botão abre os Ajustes do Sistema: ative o Ilusio na lista."])
        case .virtualCamera:
            if VirtualCamera.appIsInApplications {
                steps(["Clique em **Ativar a câmera**: os Ajustes do Sistema abrem sozinhos em Itens de Início e Extensões.",
                       "Em **Extensões de Câmera**, ative o Ilusio (o macOS pode pedir a sua senha).",
                       "Volte aqui: este item fica verde sozinho."])
            } else {
                steps(["O macOS só ativa a câmera de apps que estão em **Aplicativos**.",
                       "Clique em **Mostrar no Finder** e arraste o Ilusio para a pasta Aplicativos.",
                       "Abra o Ilusio de lá e volte a este item."])
            }
        case .virtualAudio:
            steps(["Clique em **Instalar o microfone**; o macOS pede a sua senha de administrador (uma vez só).",
                   "O áudio do Mac corta por uns 2 segundos enquanto reinicia.",
                   "Se este item não ficar verde, reinicie o Mac."])
        case .background:
            steps(["No Início, clique em **Ligar o Ilusio** e depois em **Gravar fundo**.",
                   "Saia do quadro e da frente da luz durante a contagem de 5 segundos."])
        case .gesture:
            steps(["Com o Ilusio ligado e o fundo gravado, encoste o **indicador e o médio** na testa.",
                   "Segure meio segundo: a borda da prévia fica verde, toca o som e você some.",
                   "Repita o gesto para voltar. Também dá pelo atalho ⌃⌥T."])
        case .callApp:
            VStack(alignment: .leading, spacing: 10) {
                Picker("App", selection: $callApp) {
                    ForEach(CallApp.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                steps(callApp.steps)
            }
        }
    }

    private func steps(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(LocalizedStringKey(line))  // aceita **negrito**
                }
            }
        }
        .font(.callout)
    }
}

private enum CallApp: String, CaseIterable, Identifiable {
    case meet = "Meet", zoom = "Zoom", teams = "Teams", whatsapp = "WhatsApp"
    var id: Self { self }

    var steps: [String] {
        switch self {
        case .meet:
            ["Na chamada, clique em ⋮ ▸ **Configurações**.",
             "Em **Vídeo**, câmera **Ilusio Camera** e resolução 720p.",
             "Em **Áudio**, microfone **Ilusio Mic** e desligue o cancelamento de ruído.",
             "Em **Efeitos visuais**, deixe “Sem efeito”."]
        case .zoom:
            ["Menu zoom.us ▸ **Configurações**.",
             "Em **Vídeo**, câmera **Ilusio Camera**.",
             "Em **Áudio**, microfone **Ilusio Mic** e supressão de ruído em **Baixa**."]
        case .teams:
            ["Foto do perfil ▸ **Configurações** ▸ **Dispositivos**.",
             "Câmera **Ilusio Camera** e microfone **Ilusio Mic**.",
             "Desligue a supressão de ruído."]
        case .whatsapp:
            ["Na chamada de vídeo, clique em ⌄ ao lado da câmera e escolha **Ilusio Camera**.",
             "No ⌄ do microfone, escolha **Ilusio Mic**. O alto-falante fica no do Mac."]
        }
    }
}
