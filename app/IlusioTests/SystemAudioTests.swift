import XCTest
@testable import Ilusio

final class SystemAudioTests: XCTestCase {
    func testMotorUsaOMicrofoneEscolhido() {
        XCTAssertEqual(SystemAudio.engineMic(chosen: "Microfone USB", systemDefault: "Microfone (MacBook Air)"), "Microfone USB")
    }

    func testSemEscolhaUsaOPadraoDeVerdadeDoSistema() {
        // capturado antes de o Ilusio virar o microfone do sistema
        XCTAssertEqual(SystemAudio.engineMic(chosen: nil, systemDefault: "Microfone (MacBook Air)"), "Microfone (MacBook Air)")
    }

    func testPadraoVirtualNaoServeDeMicrofone() {
        // ex.: o app fechou à força com o Ilusio Mic como padrão: o motor escolhe sozinho um microfone real
        XCTAssertNil(SystemAudio.engineMic(chosen: nil, systemDefault: "Ilusio Mic"))
        XCTAssertNil(SystemAudio.engineMic(chosen: nil, systemDefault: "BlackHole 2ch"))
        XCTAssertNil(SystemAudio.engineMic(chosen: nil, systemDefault: nil))
    }
}
