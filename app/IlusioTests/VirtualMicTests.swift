import XCTest
@testable import Ilusio

final class VirtualMicTests: XCTestCase {
    func testScriptUsaQuotedFormEInstalaNoHAL() {
        let script = VirtualMic.installScript(source: "/Applications/Ilusio.app/Contents/Resources/IlusioMic.driver")
        XCTAssertTrue(script.contains("quoted form of src"))
        XCTAssertTrue(script.contains("/Library/Audio/Plug-Ins/HAL/IlusioMic.driver"))
        XCTAssertTrue(script.contains("killall coreaudiod"))
        XCTAssertTrue(script.contains("with administrator privileges"))
    }

    func testCaminhoComAspasNaoEscapaDaString() {
        // um caminho malicioso não pode fechar a string do AppleScript e injetar comandos
        let script = VirtualMic.installScript(source: #"/tmp/x" & do shell script "rm -rf ~" & "\.driver"#)
        XCTAssertTrue(script.contains(#"set src to "/tmp/x\" & do shell script \"rm -rf ~\" & \"\\.driver""#))
    }
}
