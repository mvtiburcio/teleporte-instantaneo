import XCTest
@testable import Teleporte

@MainActor
final class EngineClientTests: XCTestCase {
    func testDecodificaState() {
        let ev = EngineEvent.parse(#"{"event": "state", "hidden": true, "bg_ready": false, "bg_countdown": 3.5, "gesture": false, "fps": 29.7}"#)
        XCTAssertEqual(ev?.event, "state")
        XCTAssertEqual(ev?.hidden, true)
        XCTAssertEqual(ev?.bgReady, false)
        XCTAssertEqual(ev?.bgCountdown, 3.5)
        XCTAssertEqual(ev?.fps, 29.7)
    }

    func testLinhaInvalidaViraNil() {
        XCTAssertNil(EngineEvent.parse("Microfone 'X' + teleporte"))
        XCTAssertNil(EngineEvent.parse(#"{"sem": "event"}"#))
    }

    func testMotorDeVerdade() throws {
        guard Repo.python != nil, let (exe, args) = EngineClient.command(repoDir: Repo.root.path) else {
            throw XCTSkip("sem .venv do motor")
        }
        let shm = NSTemporaryDirectory() + "engine-\(UUID().uuidString).shm"
        let fb = try FrameBuffer(path: shm, width: 1280, height: 720)
        let client = EngineClient()
        let ready = expectation(description: "ready"), state = expectation(description: "state"), exited = expectation(description: "exit")
        state.assertForOverFulfill = false
        client.onEvent = { ev in
            if ev.event == "ready" { ready.fulfill() }
            if ev.event == "state" { state.fulfill() }
        }
        var code: Int32 = -1
        client.onExit = { code = $0; exited.fulfill() }
        try client.start(executable: exe, arguments: args, log: URL(fileURLWithPath: NSTemporaryDirectory() + "engine-test.log"))
        wait(for: [ready], timeout: 60)
        client.send("start", ["shm": shm, "output": NSNull(), "vcam": false])
        let frame = [UInt8](repeating: 90, count: fb.slotSize)
        var out = [UInt8](repeating: 0, count: fb.slotSize), last: UInt64 = 0, got = false
        let deadline = Date().addingTimeInterval(30)
        while !got && Date() < deadline {
            frame.withUnsafeBytes { fb.write(.input, from: $0.baseAddress!, bytesPerRow: 1280 * 4) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            got = out.withUnsafeMutableBytes { fb.read(.output, last: &last, into: $0.baseAddress!) }
        }
        XCTAssertTrue(got, "o motor não devolveu frame")
        XCTAssertEqual(out[0], 90)  // sem fundo gravado: passa direto (B do primeiro pixel)
        wait(for: [state], timeout: 5)
        client.stop()
        wait(for: [exited], timeout: 15)
        XCTAssertEqual(code, 0)
    }
}
