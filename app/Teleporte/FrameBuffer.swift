import Foundation
import Synchronization

/// Memória compartilhada de frames com o motor (mesmo layout do ipc.py): cabeçalho de 64 bytes
/// e dois slots BGRA (in = câmera, out = resultado), cada um com seqlock: seq ímpar = escrevendo.
final class FrameBuffer: @unchecked Sendable {
    enum Slot {
        case input, output
        var seqOffset: Int { self == .input ? 16 : 24 }
    }

    static let headerSize = 64
    let width: Int, height: Int, slotSize: Int
    private let base: UnsafeMutableRawPointer
    private let total: Int

    init(path: String, width: Int, height: Int) throws {
        self.width = width
        self.height = height
        slotSize = width * height * 4
        total = Self.headerSize + 2 * slotSize
        // sem O_TRUNC: encolher um arquivo ainda mapeado (captura ou motor antigos) dá SIGBUS em quem escreve nele
        let fd = open(path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard ftruncate(fd, off_t(total)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let p = mmap(nil, total, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard let p, p != MAP_FAILED else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        base = p
        base.copyMemory(from: Array("TLPT".utf8), byteCount: 4)
        for (offset, value) in [(4, 1), (8, width), (12, height)] {
            base.storeBytes(of: UInt32(value).littleEndian, toByteOffset: offset, as: UInt32.self)
        }
        setSeq(.input, 0)
        setSeq(.output, 0)
    }

    deinit { munmap(base, total) }

    private func seq(_ s: Slot) -> UInt64 { base.load(fromByteOffset: s.seqOffset, as: UInt64.self) }
    private func setSeq(_ s: Slot, _ v: UInt64) { base.storeBytes(of: v, toByteOffset: s.seqOffset, as: UInt64.self) }
    private func slot(_ s: Slot) -> UnsafeMutableRawPointer { base + Self.headerSize + (s == .input ? 0 : slotSize) }

    /// Copia um frame BGRA para o slot; bytesPerRow pode ser maior que width*4 (linhas alinhadas).
    func write(_ s: Slot, from src: UnsafeRawPointer, bytesPerRow: Int) {
        let v = seq(s) & ~1  // um escritor por slot
        setSeq(s, v + 1)
        atomicMemoryFence(ordering: .sequentiallyConsistent)
        let dst = slot(s), row = width * 4
        if bytesPerRow == row {
            dst.copyMemory(from: src, byteCount: slotSize)
        } else {
            for y in 0..<height { (dst + y * row).copyMemory(from: src + y * bytesPerRow, byteCount: row) }
        }
        atomicMemoryFence(ordering: .sequentiallyConsistent)
        setSeq(s, v + 2)
    }

    /// Copia o frame novo do slot para dst. Falso se não há frame novo ou se ele foi rasgado durante a cópia.
    func read(_ s: Slot, last: inout UInt64, into dst: UnsafeMutableRawPointer) -> Bool {
        let v = seq(s)
        atomicMemoryFence(ordering: .acquiring)
        guard v & 1 == 0, v != last else { return false }
        dst.copyMemory(from: slot(s), byteCount: slotSize)
        atomicMemoryFence(ordering: .acquiring)
        guard seq(s) == v else { return false }
        last = v
        return true
    }
}
