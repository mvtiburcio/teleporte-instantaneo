import SwiftUI

/// Aba "Apoiar": um Pix estático sem valor (quem paga escolhe quanto), sem conta e sem cadastro.
struct SupportView: View {
    @State private var copied = false
    private let payload = PixCode.configured

    var body: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 36) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Curtiu o Ilusio? 💛").font(.largeTitle.bold())
                    Text("O Ilusio é grátis e de código aberto. Se ele te fez rir numa reunião, um Pix de qualquer valor ajuda a manter o projeto.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let payload {
                        Button(copied ? "Copiado! Obrigado 💛" : "Copiar Pix copia-e-cola", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(payload, forType: .string)
                            copied = true
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                        .controlSize(.large)
                        Text("Abra o app do seu banco, escolha Pix ▸ Ler QR code ou Pix copia e cola, e digite o valor que quiser.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 380, alignment: .leading)

                if let payload, let qr = PixCode.qrImage(payload) {
                    VStack(spacing: 10) {
                        Image(decorative: qr, scale: 1)
                            .interpolation(.none)  // QR nítido
                            .resizable()
                            .frame(width: 220, height: 220)
                            .padding(16)
                            .background(.white, in: .rect(cornerRadius: 20))  // fundo branco: leitura garantida em tema escuro
                        Text("Aponte a câmera do banco").font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
                }
            }
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Apoiar")
        .animation(.smooth, value: copied)
    }
}
