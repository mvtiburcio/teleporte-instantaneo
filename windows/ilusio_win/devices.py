# devices.py — câmeras reais, com nome e índice do OpenCV (as virtuais nunca viram fonte: realimentariam a saída)
import sys
from dataclasses import dataclass

VIRTUAL = ("Ilusio Camera", "OBS Virtual Camera")
INTEGRATED = ("Integrated", "Integrada", "FaceTime", "Built-in")  # câmera do próprio notebook


@dataclass(frozen=True)
class Camera:
    index: int
    name: str


def real_cameras(cameras):
    return [c for c in cameras if not any(v in c.name for v in VIRTUAL)]


def pick_default(cameras, saved=None):
    """A salva, se ainda estiver ligada; senão a integrada; senão a primeira."""
    return (next((c for c in cameras if c.name == saved), None)
            or next((c for c in cameras if any(k in c.name for k in INTEGRATED)), None)
            or (cameras[0] if cameras else None))


def backend():
    import cv2
    return cv2.CAP_MSMF if sys.platform == "win32" else cv2.CAP_ANY


def list_cameras():
    """Câmeras reais do sistema, sem repetir nome (o Windows lista a mesma câmera em mais de uma API)."""
    from cv2_enumerate_cameras import enumerate_cameras
    seen, cams = set(), []
    for info in enumerate_cameras(backend()):
        if info.name not in seen:
            seen.add(info.name)
            cams.append(Camera(info.index, info.name))
    return real_cameras(cams)


def list_mics():
    """Microfones de verdade (sem as saídas virtuais do VB-Cable/BlackHole/Ilusio), sem repetir nome."""
    import sounddevice as sd
    import teleporte as tp
    names = []
    for d in sd.query_devices():
        if d["max_input_channels"] > 0 and not any(v in d["name"] for v in tp.VIRTUAL_INS) and d["name"] not in names:
            names.append(d["name"])
    return names
