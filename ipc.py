# ipc.py — ponte entre o app e o motor: frames por memória compartilhada, comandos e eventos em JSON por linha
import json, mmap, os, struct, sys
import numpy as np

MAGIC, VERSION = b"TLPT", 1
HDR = struct.Struct("<4sIII")  # magic, version, width, height
HDR_SIZE = 64
SEQ_OFF = {"in": 16, "out": 24}
COMMANDS = {"start", "capture_bg", "toggle", "reappear", "set", "test_sound", "stop"}

class FrameShm:
    # dois slots BGRA (in = câmera, out = resultado), cada um com seqlock: seq ímpar = escrevendo
    # ponytail: leitura por polling; semáforo POSIX se o uso de CPU aparecer no perfil
    def __init__(self, path, w, h, create=False):
        size = w * h * 4
        total = HDR_SIZE + 2 * size
        fd = os.open(path, os.O_RDWR | (os.O_CREAT if create else 0), 0o600)
        try:
            if create:
                os.ftruncate(fd, total)
            self.mm = mmap.mmap(fd, total)
        finally:
            os.close(fd)
        if create:
            HDR.pack_into(self.mm, 0, MAGIC, VERSION, w, h)
            struct.pack_into("<QQ", self.mm, SEQ_OFF["in"], 0, 0)
        if HDR.unpack_from(self.mm, 0) != (MAGIC, VERSION, w, h):
            self.mm.close()
            raise ValueError(f"frames.shm incompatível com {w}x{h} v{VERSION}")
        self.view = {s: np.frombuffer(self.mm, np.uint8, size, HDR_SIZE + i * size).reshape(h, w, 4)
                     for i, s in enumerate(("in", "out"))}
        self.last = {"in": 0, "out": 0}

    def _seq(self, slot):
        return struct.unpack_from("<Q", self.mm, SEQ_OFF[slot])[0]

    def _set_seq(self, slot, v):
        struct.pack_into("<Q", self.mm, SEQ_OFF[slot], v)

    def write(self, slot, frame):
        s = self._seq(slot) & ~1  # um escritor por slot: seq par aqui
        self._set_seq(slot, s + 1)
        self.view[slot][...] = frame
        self._set_seq(slot, s + 2)

    def read(self, slot):
        s = self._seq(slot)
        if s & 1 or s == self.last[slot]:
            return None
        frame = self.view[slot].copy()
        if self._seq(slot) != s:
            return None  # o escritor passou por cima durante a cópia
        self.last[slot] = s
        return frame

    def close(self):
        self.view = None  # as views seguram o buffer: soltar antes de fechar
        self.mm.close()

def parse_command(line):
    msg = json.loads(line)
    if not isinstance(msg, dict) or msg.get("cmd") not in COMMANDS:
        raise ValueError(f"comando inválido: {line.strip()[:80]}")
    return msg

def emit(event, out=sys.stdout, **fields):
    out.write(json.dumps({"event": event, **fields}) + "\n")
    out.flush()
