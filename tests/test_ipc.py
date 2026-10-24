import io, json, os, sys, tempfile, unittest
from unittest import mock
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ipc import FrameShm, parse_command, emit, SEQ_OFF

W, H = 64, 48

class FrameShmTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "frames.shm")
        self.shm = FrameShm(self.path, W, H, create=True)
        self.frame = np.random.default_rng(1).integers(0, 255, (H, W, 4), dtype=np.uint8)

    def tearDown(self):
        self.shm.close()
        self.dir.cleanup()

    def test_roundtrip_e_sem_frame_novo(self):
        self.assertIsNone(self.shm.read("in"))
        self.shm.write("in", self.frame)
        np.testing.assert_array_equal(self.shm.read("in"), self.frame)
        self.assertIsNone(self.shm.read("in"))  # mesmo seq: nada novo
        self.assertIsNone(self.shm.read("out"))  # slots independentes

    def test_outro_processo_le_o_que_foi_escrito(self):
        self.shm.write("out", self.frame)
        other = FrameShm(self.path, W, H)
        try:
            np.testing.assert_array_equal(other.read("out"), self.frame)
        finally:
            other.close()

    def test_seq_impar_descarta(self):
        self.shm._set_seq("in", 1)  # escritor no meio da cópia
        self.assertIsNone(self.shm.read("in"))

    def test_seq_mudou_durante_a_copia_descarta(self):
        self.shm.write("in", self.frame)  # seq = 2
        with mock.patch.object(self.shm, "_seq", side_effect=[2, 4]):
            self.assertIsNone(self.shm.read("in"))

    def test_cabecalho_incompativel(self):
        self.shm.mm[0:4] = b"XXXX"
        with self.assertRaises(ValueError):
            FrameShm(self.path, W, H)

class ProtocolTest(unittest.TestCase):
    def test_comando_valido(self):
        self.assertEqual(parse_command('{"cmd": "toggle"}\n'), {"cmd": "toggle"})

    def test_comandos_invalidos(self):
        for line in ['nao é json', '[1]', '{"cmd": "rm"}', '{}']:
            with self.assertRaises(ValueError):
                parse_command(line)

    def test_emit_uma_linha_json(self):
        out = io.StringIO()
        emit("state", out=out, hidden=False, fps=29.5)
        self.assertEqual(out.getvalue().count("\n"), 1)
        self.assertEqual(json.loads(out.getvalue()), {"event": "state", "hidden": False, "fps": 29.5})

if __name__ == "__main__":
    unittest.main()
