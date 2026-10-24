import XCTest
@testable import Ilusio

final class SetupTests: XCTestCase {
    func testContagem() {
        XCTAssertEqual(SetupChecks().doneCount, 0)
        let all = SetupChecks(camera: true, mic: true, obsInstalled: true, virtualCamera: true, virtualAudio: true,
                              background: true, gesture: true, callApp: true)
        XCTAssertEqual(all.doneCount, SetupItem.allCases.count)
        XCTAssertNil(all.firstPending)
    }

    func testPrimeiroPendenteNaOrdem() {
        var c = SetupChecks(camera: true, mic: true)
        XCTAssertEqual(c.firstPending, .virtualCamera)
        c.virtualCamera = true
        c.virtualAudio = true
        c.gesture = true  // fora de ordem: o fundo ainda vem antes
        XCTAssertEqual(c.firstPending, .background)
    }

    func testCameraVirtualSoContaComODispositivo() {
        let c = SetupChecks(obsInstalled: true)  // OBS instalado, extensão ainda não aprovada
        XCTAssertFalse(c.isDone(.virtualCamera))
    }
}
