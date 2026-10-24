import XCTest
@testable import Ilusio

final class VirtualMicTests: XCTestCase {
    func testScriptUsaQuotedFormEInstalaNoHAL() {
        let script = VirtualMic.installScript(source: "/Applications/Ilusio.app/Contents/Resources/IlusioMic.driver")
        XCTAssertTrue(script.contains("quoted form of src"))
        XCTAssertTrue(script.contains("/Library/Audio/Plug-Ins/HAL/IlusioMic.driver"))
        XCTAssertTrue(script.contains("&& (killall coreaudiod || true)"))  // cópia falhando ainda é erro; só o reinício é tolerado
        XCTAssertTrue(script.contains("with administrator privileges"))
    }

    func testCaminhoComAspasNaoEscapaDaString() {
        // um caminho malicioso não pode fechar a string do AppleScript e injetar comandos
        let script = VirtualMic.installScript(source: #"/tmp/x" & do shell script "rm -rf ~" & "\.driver"#)
        XCTAssertTrue(script.contains(#"set src to "/tmp/x\" & do shell script \"rm -rf ~\" & \"\\.driver""#))
    }

    func testAtualizaSoQuandoAVersaoInstaladaDifere() {
        XCTAssertTrue(VirtualMic.needsUpdate(installed: "0.7.1", bundled: "0.7.2"))
        XCTAssertFalse(VirtualMic.needsUpdate(installed: "0.7.2", bundled: "0.7.2"))
        XCTAssertFalse(VirtualMic.needsUpdate(installed: nil, bundled: "0.7.2"))  // não instalado: é "instalar"
        XCTAssertFalse(VirtualMic.needsUpdate(installed: "0.7.2", bundled: nil))  // build sem driver embutido
    }
}
