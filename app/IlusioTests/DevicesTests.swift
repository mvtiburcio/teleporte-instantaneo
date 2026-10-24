import XCTest
@testable import Ilusio

final class DevicesTests: XCTestCase {
    let iphone = Devices.Item(id: "iphone", name: "iPhone de Marcus Camera", builtIn: false)
    let mac = Devices.Item(id: "mac", name: "FaceTime HD Camera", builtIn: true)
    let usb = Devices.Item(id: "usb", name: "Logitech C920", builtIn: false)

    func testPrefereAEscolhaSalva() {
        XCTAssertEqual(Devices.pick([iphone, mac, usb], saved: "usb")?.id, "usb")
    }

    func testSemEscolhaPrefereAEmbutidaMesmoComIPhonePrimeiro() {
        XCTAssertEqual(Devices.pick([iphone, mac], saved: nil)?.id, "mac")
    }

    func testEscolhaDesconectadaVoltaParaAEmbutida() {
        XCTAssertEqual(Devices.pick([iphone, mac], saved: "usb")?.id, "mac")
    }

    func testSemEmbutidaUsaAPrimeiraESemNadaNil() {
        XCTAssertEqual(Devices.pick([usb, iphone], saved: nil)?.id, "usb")
        XCTAssertNil(Devices.pick([], saved: "mac"))
    }

    func testVirtuaisFicamDeFora() {
        for name in ["OBS Virtual Camera", "Ilusio Camera", "BlackHole 2ch", "Ilusio Mic"] {
            XCTAssertTrue(Devices.isVirtual(name), name)
        }
        XCTAssertFalse(Devices.isVirtual("FaceTime HD Camera"))
    }
}
