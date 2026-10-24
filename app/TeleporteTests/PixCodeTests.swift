import XCTest
@testable import Teleporte

final class PixCodeTests: XCTestCase {
    func testCRC16VetorPadrao() {
        XCTAssertEqual(PixCode.crc16("123456789"), "29B1")
    }

    func testExemploDoManualDoBCB() {
        let payload = PixCode.payload(key: "123e4567-e12b-12d1-a456-426655440000", name: "Fulano de Tal", city: "BRASILIA")
        XCTAssertEqual(payload, "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000"
                       + "5204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D")
    }

    func testNomeECidadeSemAcentoENoLimite() {
        XCTAssertEqual(PixCode.ascii("São João do Caiçara Mirim", max: 15), "Sao Joao do Cai")
        let payload = PixCode.payload(key: "k", name: "Teleporte Instantâneo", city: "Recife")
        XCTAssertTrue(payload.contains("5921Teleporte Instantaneo6006Recife"))
    }
}
