import XCTest
@testable import Ilusio

final class FrameRateTests: XCTestCase {
    typealias F = CameraCapture.FormatInfo

    func testEscolheOMenorFormatoHDQueAguentaAFps() {
        let formats = [F(width: 1920, height: 1080, maxFPS: 60), F(width: 1280, height: 720, maxFPS: 60), F(width: 640, height: 480, maxFPS: 120)]
        XCTAssertEqual(CameraCapture.pickFormat(formats, fps: 60), 1)  // 720p a 60: menor que dá conta
    }

    func testSemFormatoNaFpsPedidaFicaComOMaisRapidoEmHD() {
        let formats = [F(width: 1280, height: 720, maxFPS: 30), F(width: 1920, height: 1080, maxFPS: 24), F(width: 640, height: 480, maxFPS: 60)]
        XCTAssertEqual(CameraCapture.pickFormat(formats, fps: 60), 0)  // 480p a 60 não serve: perde resolução
    }

    func testSemHDUsaOMaiorDisponivel() {
        XCTAssertEqual(CameraCapture.pickFormat([F(width: 640, height: 480, maxFPS: 30), F(width: 800, height: 600, maxFPS: 30)], fps: 30), 1)
        XCTAssertNil(CameraCapture.pickFormat([], fps: 30))
    }

    func testFpsDentroDeUmaFaixaDaCamera() {
        XCTAssertEqual(CameraCapture.clampFPS(15, ranges: [(1, 30)]), 15)
        XCTAssertEqual(CameraCapture.clampFPS(15, ranges: [(30, 30), (60, 60)]), 30)  // faixas fixas: a mais perto
        XCTAssertEqual(CameraCapture.clampFPS(60, ranges: [(1, 30)]), 30)
        XCTAssertEqual(CameraCapture.clampFPS(24, ranges: []), 24)
    }
}
