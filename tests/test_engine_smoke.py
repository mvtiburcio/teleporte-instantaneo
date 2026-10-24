import json, os, subprocess, sys, tempfile, threading, time, unittest
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from ipc import FrameShm

class EngineSmokeTest(unittest.TestCase):
    def test_ipc_ida_e_volta(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "frames.shm")
            shm = FrameShm(path, 1280, 720, create=True)
            p = subprocess.Popen([sys.executable, os.path.join(ROOT, "teleporte.py"), "--ipc"],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            watchdog = threading.Timer(60, p.kill)  # readline bloqueia pra sempre se o motor não responder
            watchdog.start()
            try:
                self.assertEqual(json.loads(p.stdout.readline() or "{}").get("event"), "ready")
                p.stdin.write(json.dumps({"cmd": "start", "shm": path, "output": None, "vcam": False}) + "\n")
                p.stdin.flush()
                frame = np.full((720, 1280, 4), 90, np.uint8)
                got, deadline = None, time.time() + 30
                while got is None and time.time() < deadline:
                    shm.write("in", frame)
                    time.sleep(0.03)
                    got = shm.read("out")
                self.assertIsNotNone(got, "o motor não devolveu frame no slot out")
                np.testing.assert_array_equal(got[..., :3], frame[..., :3])  # sem fundo gravado: passa direto
                time.sleep(0.3)  # tempo pra sair ao menos um state
                out, _ = p.communicate('{"cmd": "set", "gain": "alto"}\n{"cmd": "stop"}\n', timeout=15)
                events = [json.loads(l) for l in out.splitlines()]  # linha entrelaçada quebraria o json.loads
                self.assertIn("state", [e["event"] for e in events])
                self.assertIn("bad_command", [e.get("code") for e in events])  # campo errado não derruba o motor
                self.assertEqual(p.returncode, 0)
            finally:
                watchdog.cancel()
                if p.poll() is None:
                    p.kill()
                shm.close()

if __name__ == "__main__":
    unittest.main()
