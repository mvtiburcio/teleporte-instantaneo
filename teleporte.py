# teleporte.py — teletransporte instantâneo: dois dedos na testa e você some (e volta)
import os, time, wave, queue, subprocess, warnings
warnings.filterwarnings("ignore", category=UserWarning)  # aviso de depreciação do protobuf
import cv2, numpy as np
import mediapipe as mp
import pyvirtualcam
import sounddevice as sd

SOUND = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sons", "teleport.wav")  # gerado por tools/preparar_som.py
SOUND_LEAD = 0.1  # do disparo até o "vuush" do som: o efeito começa nesse ponto
FX_S = 0.9        # duração do efeito, casada com o som
HOLD_S = 0.25     # quanto tempo segurar o gesto pra disparar
REACH = 1.5       # tolerância dos dedos até a testa (em distâncias entre os olhos): suba se não reconhecer
GROW_PX = 31      # quanto a máscara cresce além do contorno: suba se sobrar borda/halo
BG_DELAY_S = 5    # contagem entre apertar B e gravar o fundo
SFX_GAIN = 0.8    # volume do teleporte que vai pra chamada, em relação ao microfone
W, H = 1280, 720

rng = np.random.default_rng()
kernel = np.ones((GROW_PX, GROW_PX), np.uint8)

# o Meet/WhatsApp cortam o que sai do alto-falante (cancelamento de eco), então o script vira o microfone:
# mistura microfone + som do teleporte e manda pro BlackHole, que a chamada usa como microfone
SR = 48000   # taxa nativa do BlackHole: com outra taxa o CoreAudio dá erro -50
BLOCK = 480  # 10 ms
mic_q = queue.Queue()
sfx, sfx_pos = None, None

def load_sfx():
    with wave.open(SOUND) as wf:
        src_sr = wf.getframerate()
        raw = np.frombuffer(wf.readframes(wf.getnframes()), np.int16).reshape(-1, wf.getnchannels())[:, :2] / 32768
    t_src, t_dst = np.arange(len(raw)) / src_sr, np.arange(int(len(raw) * SR / src_sr)) / SR
    return np.stack([np.interp(t_dst, t_src, raw[:, c]) for c in range(raw.shape[1])], 1).astype(np.float32) * SFX_GAIN

# microfone e BlackHole têm relógios diferentes: um fluxo duplex só com os dois devolve lixo (NaN),
# então são dois fluxos ligados por uma fila curta
def on_mic(indata, frames, t, status):
    mic_q.put(indata[:, 0].copy())
    while mic_q.qsize() > 5:  # não deixa o atraso crescer
        mic_q.get_nowait()

def on_audio(outdata, frames, t, status):
    global sfx_pos
    try:
        outdata[:] = mic_q.get_nowait()[:, None]
    except queue.Empty:
        outdata.fill(0)
    if sfx_pos is not None:
        chunk = sfx[sfx_pos:sfx_pos + frames]
        outdata[:len(chunk)] += chunk
        sfx_pos = sfx_pos + frames if sfx_pos + frames < len(sfx) else None

def open_mic_bridge():
    devs = sd.query_devices()
    bh = next((i for i, d in enumerate(devs) if "BlackHole" in d["name"] and d["max_output_channels"] >= 2), None)
    if bh is None:
        print("BlackHole não instalado: o som do teleporte toca só aqui, a chamada não ouve.")
        return None
    mic = sd.default.device[0]
    if mic < 0 or "BlackHole" in devs[mic]["name"]:  # sem entrada padrão, ou entrada do sistema já no BlackHole
        mic = next((i for i, d in enumerate(devs) if d["max_input_channels"] > 0 and "BlackHole" not in d["name"]), None)
    if mic is None:
        print("Nenhum microfone encontrado: a câmera funciona, mas a chamada não recebe áudio deste script.")
        return None
    print(f"Microfone '{devs[mic]['name']}' + teleporte -> BlackHole. Na chamada, escolha o microfone 'BlackHole 2ch'.")
    streams = (sd.InputStream(device=mic, samplerate=SR, channels=1, dtype="float32", blocksize=BLOCK, callback=on_mic),
               sd.OutputStream(device=bh, samplerate=SR, channels=2, dtype="float32", blocksize=BLOCK, callback=on_audio))
    for s in streams:
        s.start()
    return streams

def open_webcam(cam):
    # com a câmera virtual ligada, o OBS entra na lista de câmeras e muda os índices;
    # envia magenta pra ela e fica com a primeira câmera que devolve outra coisa
    probe = np.full((H, W, 3), (255, 0, 255), np.uint8)
    for idx in range(4):
        cap = cv2.VideoCapture(idx)
        ok = False
        for _ in range(5):
            cam.send(probe)
            ok, f = cap.read()
        if ok and np.abs(f.mean(axis=(0, 1)) - (255, 0, 255)).max() > 60:
            return cap
        cap.release()
    raise SystemExit("Webcam não encontrada: libere o acesso em Ajustes > Privacidade e Segurança > Câmera.")

def is_teleport_sign(hand, face):
    # indicador e médio esticados e juntos, anelar e mindinho dobrados, pontas na testa
    p = np.array([(l.x * W, l.y * H) for l in hand.landmark])
    d = lambda a, b: np.linalg.norm(p[a] - p[b])
    if not (d(8, 0) > d(6, 0) and d(12, 0) > d(10, 0) and d(16, 0) < d(14, 0) and d(20, 0) < d(18, 0)):
        return False
    if d(8, 12) > d(5, 9) * 1.8:
        return False
    k = face.location_data.relative_keypoints
    eye_r, eye_l = np.array([k[0].x * W, k[0].y * H]), np.array([k[1].x * W, k[1].y * H])
    eyes = np.linalg.norm(eye_r - eye_l)
    forehead = (eye_r + eye_l) / 2 - (0, eyes * 0.6)
    return np.linalg.norm((p[8] + p[12]) / 2 - forehead) < eyes * REACH

def person_mask(seg, rgb):
    # máscara da pessoa, crescida e suavizada pra não sobrar contorno
    m = seg.process(rgb).segmentation_mask
    return cv2.GaussianBlur(cv2.dilate((m > 0.1).astype(np.float32), kernel), (21, 21), 0)

def teleport(frame, bg, m, p):
    # p: 0 = você inteiro, 1 = sumiu. borrão vertical + riscos verticais + piscadas, estilo DBZ;
    # o resto da imagem é sempre o fundo gravado, pra não sobrar sombra
    person = cv2.blur(frame, (1, 1 + int(80 * p))).astype(np.float32)
    alpha = min((1 - p) * 1.6, 1.0) * (rng.random() > p * 0.6)
    m3 = m[..., None] * alpha
    out = (bg * (1 - m3) + person * m3).astype(np.uint8)
    ys, xs = np.nonzero(m[::4, ::4] > 0.5)
    n = int(250 * np.sin(np.pi * p)) if len(xs) else 0
    for i in rng.integers(0, max(len(xs), 1), n):
        x, y, L = xs[i] * 4, ys[i] * 4, int(rng.integers(40, 250))
        c = (245, 245, 255) if rng.random() < 0.6 else (25, 25, 30)
        cv2.line(out, (int(x), int(y - L // 2)), (int(x), int(y + L // 2)), c, int(rng.integers(1, 3)))
    return out

def main():
    global sfx, sfx_pos
    if not os.path.exists(SOUND):
        raise SystemExit("Som não encontrado: rode ./setup.sh (ou tools/preparar_som.py) antes.")
    sfx = load_sfx()
    seg = mp.solutions.selfie_segmentation.SelfieSegmentation(model_selection=1)
    hands = mp.solutions.hands.Hands(max_num_hands=2, model_complexity=1, min_detection_confidence=0.5)
    faces = mp.solutions.face_detection.FaceDetection(model_selection=1, min_detection_confidence=0.5)  # 1 = até ~5 m

    bg = None
    hidden, fx_start, target = False, None, False
    sign_since, last_sign, armed = None, 0.0, True
    face, face_at = None, 0.0
    n_frame, sign = 0, False
    bg_at = None

    try:
        vcam = pyvirtualcam.Camera(W, H, fps=30, fmt=pyvirtualcam.PixelFormat.BGR)
    except RuntimeError as e:
        raise SystemExit(f"Câmera virtual indisponível ({e}). Feche o OBS (ou clique em 'Parar câmera virtual') e rode de novo.")

    with vcam as cam:
        cap = open_webcam(cam)
        mic_bridge = open_mic_bridge()  # guarda a referência: os fluxos de áudio vivem enquanto ela existir
        print("Na chamada, escolha a câmera 'OBS Virtual Camera'.")
        print('Com a janela "teleporte" em foco, aperte B e, em 5 s, saia do quadro e da frente da luz (grava o fundo).')
        print("Dois dedos na testa = some / volta. R = voltar na hora, Q = sair.")
        while True:
            ok, frame = cap.read()
            if not ok:
                print("A câmera parou de enviar imagem.")
                break
            if frame.shape[:2] != (H, W):
                frame = cv2.resize(frame, (W, H))
            now = time.time()
            rgb = None  # convertido só quando algum modelo precisa, e uma vez por frame

            n_frame += 1
            if fx_start is not None:
                sign = False
            elif n_frame % 2 == 0:  # detecta a cada 2 frames: mão + rosto custam ~25 ms e travavam o vídeo
                sign = False
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                fr = faces.process(rgb)
                if fr.detections:
                    face, face_at = fr.detections[0], now
                elif now - face_at > 1.0:
                    face = None  # a mão na testa às vezes esconde o rosto: usa o último visto por 1 s
                hr = hands.process(rgb)
                if hr.multi_hand_landmarks and face is not None:
                    sign = any(is_teleport_sign(h, face) for h in hr.multi_hand_landmarks)
            if sign:
                last_sign = now
                sign_since = sign_since or now
            elif now - last_sign > 0.3:  # tolera uns frames perdidos no meio do gesto
                sign_since, armed = None, True
            if sign_since and armed and bg is not None and now - sign_since > HOLD_S:
                subprocess.Popen(["afplay", SOUND])  # pra você ouvir
                sfx_pos = 0                          # pra chamada ouvir
                fx_start, target, armed = now + SOUND_LEAD, not hidden, False

            p = None
            if fx_start is not None:
                t = (now - fx_start) / FX_S
                if t >= 1:
                    hidden, fx_start = target, None
                elif t >= 0:
                    p = t if target else 1 - t

            if p is not None:
                rgb = rgb if rgb is not None else cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                out = teleport(frame, bg, person_mask(seg, rgb), p)
            elif hidden:
                out = bg
            else:
                out = frame
            cam.send(out)  # sem espelhar: a própria chamada espelha a sua prévia

            preview = cv2.flip(out, 1)
            if bg_at is not None:
                if now >= bg_at:
                    bg, hidden, fx_start, bg_at = frame.copy(), False, None, None
                else:
                    cv2.putText(preview, f"Fundo em {bg_at - now:.0f}s: saia do quadro e da frente da luz", (30, 60),
                                cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 255), 3)
            elif bg is None:
                cv2.putText(preview, "Aperte B pra gravar o fundo", (30, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
            if sign:
                cv2.circle(preview, (40, H - 40), 18, (0, 255, 0), -1)  # gesto reconhecido (só na prévia)
            cv2.imshow("teleporte", preview)
            k = cv2.waitKey(1) & 0xFF
            if k == ord('b'): bg_at = now + BG_DELAY_S  # a sua sombra na parede também sai na foto: dá tempo de sair da luz
            elif k == ord('r'): hidden, fx_start = False, None
            elif k == ord('q'): break

if __name__ == "__main__":
    main()
