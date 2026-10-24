# worker.py — o motor (teleporte.py) numa thread: câmera → efeito → câmera virtual + prévia e estado pra interface
import os, queue, sys, threading, time

import cv2
from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QImage

import teleporte as tp
from .devices import backend


class EngineWorker(QObject):
    frame = Signal(QImage)  # prévia espelhada, ~15 fps
    state = Signal(dict)    # hidden, bg_ready, bg_countdown, gesture, fps, vcam, audio, rms (~5 por segundo)
    failed = Signal(str)
    stopped = Signal()

    def __init__(self):
        super().__init__()
        self._cmds = queue.Queue()
        self._thread = None

    @property
    def running(self):
        return self._thread is not None and self._thread.is_alive()

    def start(self, camera_index, fps=30, gain=tp.SFX_GAIN, reach=tp.REACH, mic=None):
        if self.running:
            return
        self._cmds = queue.Queue()
        self._thread = threading.Thread(target=self._run, args=(camera_index, fps, gain, reach, mic), daemon=True)
        self._thread.start()

    def send(self, cmd, **fields):
        self._cmds.put((cmd, fields))

    def stop(self):
        self.send("stop")

    def _run(self, camera_index, fps, gain, reach, mic):
        try:
            self._loop(camera_index, fps, gain, reach, mic)
        except Exception as e:  # qualquer falha vira mensagem na tela em vez de matar o app
            self.failed.emit(f"O motor parou: {e}")
        finally:
            self.stopped.emit()

    def _loop(self, camera_index, fps, gain, reach, mic):
        if not os.path.exists(tp.SOUND):
            raise RuntimeError("som do efeito não encontrado")
        tp.sfx, tp.sfx_gain = tp.load_sfx(), gain
        cap = cv2.VideoCapture(camera_index, backend())
        if not cap.isOpened():
            raise RuntimeError("não deu pra abrir a câmera (ela está em uso por outro app?)")
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, tp.W)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, tp.H)
        cap.set(cv2.CAP_PROP_FPS, fps)
        bridge = tp.open_mic_bridge(mic or None)  # guarda a referência: os fluxos de áudio vivem enquanto ela existir
        vcam = self._open_vcam(fps)
        engine = tp.Teleporter(tp.fire_sound)
        engine.reach = reach
        next_state, t0, frames, n = 0.0, time.time(), 0, 0
        try:
            while True:
                try:
                    cmd, f = self._cmds.get_nowait()
                except queue.Empty:
                    cmd = None
                now = time.time()
                if cmd == "stop":
                    break
                elif cmd == "capture_bg": engine.capture_bg(now, f.get("delay", tp.BG_DELAY_S))
                elif cmd == "toggle": engine.fire(now)
                elif cmd == "reappear": engine.reappear()
                elif cmd == "test_sound": tp.fire_sound()
                elif cmd == "set":
                    tp.sfx_gain = f.get("gain", tp.sfx_gain)
                    engine.reach = f.get("reach", engine.reach)
                ok, frame = cap.read()
                if not ok:
                    raise RuntimeError("a câmera parou de enviar imagem")
                if frame.shape[:2] != (tp.H, tp.W):
                    frame = cv2.resize(frame, (tp.W, tp.H))
                out = engine.step(frame, now)
                if vcam:
                    vcam.send(out)
                frames, n = frames + 1, n + 1
                if n % 2 == 0:
                    self.frame.emit(to_qimage(cv2.flip(out, 1)))
                if now >= next_state:
                    self.state.emit({"hidden": engine.hidden, "bg_ready": engine.bg is not None,
                                     "bg_countdown": engine.bg_countdown(now), "gesture": engine.sign,
                                     "fps": frames / max(now - t0, 1e-6), "vcam": vcam is not None,
                                     "audio": bridge is not None, "rms": tp.mic_rms,
                                     "gesture_seen": engine.gesture_seen})
                    next_state, t0, frames = now + 0.2, now, 0
        finally:
            cap.release()
            if vcam:
                vcam.close()
            for stream in bridge or ():  # microfone e saída virtual: sem isso ficam abertos até o GC
                stream.stop()
                stream.close()

    @staticmethod
    def _open_vcam(fps):
        # PR 5 troca pela Ilusio Camera no Windows 11; até lá, a OBS Virtual Camera (se instalada)
        try:
            import pyvirtualcam
            return pyvirtualcam.Camera(tp.W, tp.H, fps=fps, fmt=pyvirtualcam.PixelFormat.BGR)
        except Exception:
            return None


def to_qimage(bgr):
    h, w = bgr.shape[:2]
    return QImage(bgr.data, w, h, bgr.strides[0], QImage.Format.Format_BGR888).copy()  # copy: o array some
