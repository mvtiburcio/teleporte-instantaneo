# pix.py — Pix estático (BR Code) sem valor, igual ao do app de Mac: quem paga escolhe quanto
import unicodedata

KEY = "d1fef5be-4e51-4a50-86fb-8810cb8bfcd4"  # chave aleatória (EVP): pública por natureza
NAME, CITY = "ILUSIO", "RECIFE"


def crc16(text):
    """CRC16-CCITT-FALSE (poly 0x1021, início 0xFFFF), hexadecimal maiúsculo."""
    crc = 0xFFFF
    for byte in text.encode():
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return f"{crc:04X}"


def ascii_only(text, limit):
    # o BR Code só aceita ASCII: tira acentos e corta no limite do campo
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()[:limit]


def payload(key, name, city):
    field = lambda id_, value: f"{id_}{len(value):02d}{value}"
    body = (field("00", "01") + field("26", field("00", "br.gov.bcb.pix") + field("01", key))
            + field("52", "0000") + field("53", "986") + field("58", "BR")
            + field("59", ascii_only(name, 25)) + field("60", ascii_only(city, 15))
            + field("62", field("05", "***")) + "6304")
    return body + crc16(body)


ILUSIO = payload(KEY, NAME, CITY)


def qr_bgr(text, scale=8, border=4):
    """QR (nível M) como imagem BGR, com margem branca pra leitura no tema escuro."""
    import cv2
    params = cv2.QRCodeEncoder.Params()
    params.correction_level = cv2.QRCodeEncoder_CORRECT_LEVEL_M
    qr = cv2.QRCodeEncoder.create(params).encode(text)
    qr = cv2.resize(qr, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
    qr = cv2.copyMakeBorder(qr, border * scale, border * scale, border * scale, border * scale, cv2.BORDER_CONSTANT, value=255)
    return cv2.cvtColor(qr, cv2.COLOR_GRAY2BGR)
