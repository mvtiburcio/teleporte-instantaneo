# gerar_demo.py — gera as imagens do README (GIF do efeito + quadro com as etapas) usando a sua webcam.
# o rosto é pixelado antes de qualquer coisa ser salva.
# uso: .venv/bin/python tools/gerar_demo.py   (siga as instruções na janela)
import os, sys, time
import cv2, numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import teleporte as tp
import mediapipe as mp

OUT = os.path.join(ROOT, "docs", "img")
COUNT_S = 7

def countdown(cap, msg):
    end = time.time() + COUNT_S
    while time.time() < end:
        ok, f = cap.read()
        f = cv2.flip(cv2.resize(f, (tp.W, tp.H)), 1)
        cv2.putText(f, f"{msg}: {end - time.time():.0f}s", (30, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
        cv2.imshow("demo", f)
        cv2.waitKey(1)
    frames = [cv2.resize(cap.read()[1], (tp.W, tp.H)).astype(np.float32) for _ in range(8)]
    return np.mean(frames, 0).astype(np.uint8)  # média de alguns frames: menos ruído

def pixelate_faces(frame):
    with mp.solutions.face_detection.FaceDetection(model_selection=1, min_detection_confidence=0.3) as fd:
        r = fd.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    if not r.detections:
        raise SystemExit("Nenhum rosto encontrado pra pixelar: nada foi salvo. Rode de novo de frente pra câmera.")
    for d in r.detections:
        b = d.location_data.relative_bounding_box
        x0, y0 = int((b.xmin - b.width * 0.3) * tp.W), int((b.ymin - b.height * 0.5) * tp.H)
        x1, y1 = int((b.xmin + b.width * 1.3) * tp.W), int((b.ymin + b.height * 1.3) * tp.H)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, tp.W), min(y1, tp.H)
        roi = frame[y0:y1, x0:x1]
        small = cv2.resize(roi, (8, 8), interpolation=cv2.INTER_AREA)
        frame[y0:y1, x0:x1] = cv2.resize(small, (x1 - x0, y1 - y0), interpolation=cv2.INTER_NEAREST)
    return frame

def label(img, text):
    img = img.copy()
    cv2.rectangle(img, (0, img.shape[0] - 44), (img.shape[1], img.shape[0]), (20, 20, 20), -1)
    cv2.putText(img, text, (14, img.shape[0] - 14), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    return img

def main():
    cap = cv2.VideoCapture(0)
    bg = countdown(cap, "Saia do quadro e da frente da luz")
    me = countdown(cap, "Volte e fique de frente pra camera")
    cap.release()
    cv2.destroyAllWindows()

    me = pixelate_faces(me)
    seg = mp.solutions.selfie_segmentation.SelfieSegmentation(model_selection=1)
    m = tp.person_mask(seg, cv2.cvtColor(me, cv2.COLOR_BGR2RGB))
    os.makedirs(OUT, exist_ok=True)

    small = lambda f: cv2.resize(f, (640, 360), interpolation=cv2.INTER_AREA)
    seq = [me] * 8 + [tp.teleport(me, bg, m, p) for p in np.linspace(0, 1, 14)] + [bg] * 12
    seq += [tp.teleport(me, bg, m, p) for p in np.linspace(1, 0, 14)] + [me] * 4
    gif = [Image.fromarray(cv2.cvtColor(small(f), cv2.COLOR_BGR2RGB)) for f in seq]
    gif[0].save(os.path.join(OUT, "efeito.gif"), save_all=True, append_images=gif[1:], duration=66, loop=0, optimize=True)

    tiles = [label(small(me), "1. Normal"), label(small(tp.teleport(me, bg, m, 0.35)), "2. Riscos + borrao"),
             label(small(tp.teleport(me, bg, m, 0.75)), "3. Piscando"), label(small(bg), "4. Sumiu (so o fundo)")]
    cv2.imwrite(os.path.join(OUT, "etapas.jpg"), np.vstack([np.hstack(tiles[:2]), np.hstack(tiles[2:])]),
                [cv2.IMWRITE_JPEG_QUALITY, 85])
    print("Salvo em", OUT)

if __name__ == "__main__":
    main()
