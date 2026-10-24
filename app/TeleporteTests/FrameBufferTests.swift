import XCTest
@testable import Teleporte

final class FrameBufferTests: XCTestCase {
    let w = 64, h = 48

    private func tmp() -> String { NSTemporaryDirectory() + "fb-\(UUID().uuidString).shm" }
    private func pattern(_ n: Int) -> [UInt8] { (0..<n).map { UInt8($0 % 251) } }

    func testCabecalhoIgualAoDoPython() throws {
        let path = tmp()
        _ = try FrameBuffer(path: path, width: w, height: h)
        let d = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(d.count, 64 + 2 * w * h * 4)
        XCTAssertEqual(Array(d[0..<4]), Array("TLPT".utf8))
        let u32 = { (o: Int) in d[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        XCTAssertEqual([u32(4), u32(8), u32(12)], [1, UInt32(w), UInt32(h)])
    }

    func testIdaEVoltaESemFrameNovo() throws {
        let fb = try FrameBuffer(path: tmp(), width: w, height: h)
        let src = pattern(fb.slotSize)
        var dst = [UInt8](repeating: 0, count: fb.slotSize)
        var lastOut: UInt64 = 0, lastIn: UInt64 = 0
        src.withUnsafeBytes { fb.write(.output, from: $0.baseAddress!, bytesPerRow: w * 4) }
        XCTAssertTrue(dst.withUnsafeMutableBytes { fb.read(.output, last: &lastOut, into: $0.baseAddress!) })
        XCTAssertEqual(dst, src)
        XCTAssertFalse(dst.withUnsafeMutableBytes { fb.read(.output, last: &lastOut, into: $0.baseAddress!) })
        XCTAssertFalse(dst.withUnsafeMutableBytes { fb.read(.input, last: &lastIn, into: $0.baseAddress!) })
    }

    func testRemovePreenchimentoDeLinha() throws {
        let fb = try FrameBuffer(path: tmp(), width: w, height: h)
        let stride = w * 4 + 16  // CVPixelBuffer costuma alinhar as linhas
        let src = pattern(stride * h)
        var dst = [UInt8](repeating: 0, count: fb.slotSize)
        var last: UInt64 = 0
        src.withUnsafeBytes { fb.write(.input, from: $0.baseAddress!, bytesPerRow: stride) }
        XCTAssertTrue(dst.withUnsafeMutableBytes { fb.read(.input, last: &last, into: $0.baseAddress!) })
        for y in [0, h / 2, h - 1] {
            XCTAssertEqual(dst[(y * w * 4)..<((y + 1) * w * 4)], src[(y * stride)..<(y * stride + w * 4)])
        }
    }

    func testPythonLeOQueOSwiftEscreveu() throws {
        guard let python = Repo.python else { throw XCTSkip("sem .venv do motor") }
        let path = tmp()
        let fb = try FrameBuffer(path: path, width: w, height: h)
        let src = pattern(fb.slotSize)
        src.withUnsafeBytes { fb.write(.input, from: $0.baseAddress!, bytesPerRow: w * 4) }
        let p = Process()
        p.executableURL = python
        p.arguments = ["-c", "import sys; sys.path.insert(0, sys.argv[1]); from ipc import FrameShm; "
                       + "print(int(FrameShm(sys.argv[2], \(w), \(h)).read('in').astype('uint64').sum()))",
                       Repo.root.path, path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        let printed = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(printed.trimmingCharacters(in: .whitespacesAndNewlines), String(src.reduce(0) { $0 + Int($1) }), errors)
    }
}

/// Raiz do repositório e o python do motor (o .venv fica no checkout principal quando se trabalha numa worktree).
enum Repo {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var python: URL? {
        [root, root.appendingPathComponent("../..").standardizedFileURL]  // ver EngineClient.command: não resolver o symlink do python
            .map { $0.appendingPathComponent(".venv/bin/python") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
