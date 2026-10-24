import CoreImage.CIFilterBuiltins
import Foundation

/// Pix estático (BR Code EMV) sem valor: quem paga escolhe quanto. Não usa API nem chave secreta;
/// só a chave Pix, que é pública por natureza (por isso uma chave aleatória, nunca CPF ou telefone).
enum PixCode {
    static func payload(key: String, name: String, city: String) -> String {
        func field(_ id: String, _ value: String) -> String { id + String(format: "%02d", value.utf8.count) + value }
        let body = field("00", "01")
            + field("26", field("00", "br.gov.bcb.pix") + field("01", key))
            + field("52", "0000")
            + field("53", "986")
            + field("58", "BR")
            + field("59", ascii(name, max: 25))
            + field("60", ascii(city, max: 15))
            + field("62", field("05", "***"))
            + "6304"
        return body + crc16(body)
    }

    /// CRC16-CCITT-FALSE (poly 0x1021, início 0xFFFF), em hexadecimal maiúsculo.
    static func crc16(_ text: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in text.utf8 {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return String(format: "%04X", crc)
    }

    /// O BR Code só aceita ASCII: tira acentos e corta no limite do campo.
    static func ascii(_ text: String, max: Int) -> String {
        String(text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR")).filter(\.isASCII).prefix(max))
    }

    static func qrImage(_ payload: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    /// Dados do recebedor, vindos dos build settings PIX_KEY, PIX_NAME e PIX_CITY (project.yml).
    static var configured: String? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let key = info["PixKey"] as? String, !key.isEmpty else { return nil }
        return payload(key: key, name: info["PixName"] as? String ?? "", city: info["PixCity"] as? String ?? "")
    }
}
