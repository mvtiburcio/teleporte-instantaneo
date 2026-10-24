# teleporte.py — teletransporte instantâneo: dois dedos na testa e você some (e volta)
import os, sys, time, wave, queue, threading, subprocess, warnings
warnings.filterwarnings("ignore", category=UserWarning)  # aviso de depreciação do protobuf
import types
# o MediaPipe importa o matplotlib só pra desenhar gráficos (nunca usado aqui); congelado, ele ainda reconstruía
# o cache de fontes a cada abertura (~10 s). Um módulo vazio no lugar corta isso
for _name in ("matplotlib", "matplotlib.pyplot"):
    sys.modules.setdefault(_name, types.ModuleType(_name))
sys.modules["matplotlib"].pyplot = sys.modules["matplotlib.pyplot"]
import cv2, numpy as np
import mediapipe as mp
import pyvirtualcam
import sounddevice as sd
from ipc import FrameShm, parse_command, emit

# congelado (PyInstaller, dentro do Ilusio.app) os arquivos ficam em sys._MEIPASS; senão, ao lado deste arquivo
BASE = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
SOUND = os.path.join(BASE, "sons", "teleport.wav")  # gerado por tools/preparar_som.py
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
VIRTUAL_OUTS = ("Ilusio Mic", "BlackHole")  # saída virtual própria (PR 4) ou BlackHole
mic_q = queue.Queue()
sfx, sfx_pos, sfx_gain, mic_rms = None, None, SFX_GAIN, 0.0

def load_sfx():
    with wave.open(SOUND) as wf:
        src_sr = wf.getframerate()
        raw = np.frombuffer(wf.readframes(wf.getnframes()), np.int16).reshape(-1, wf.getnchannels())[:, :2] / 32768
    t_src, t_dst = np.arange(len(raw)) / src_sr, np.arange(int(len(raw) * SR / src_sr)) / SR
    return np.stack([np.interp(t_dst, t_src, raw[:, c]) for c in range(raw.shape[1])], 1).astype(np.float32)

# microfone e BlackHole têm relógios diferentes: um fluxo duplex só com os dois devolve lixo (NaN),
# então são dois fluxos ligados por uma fila curta
def on_mic(indata, frames, t, status):
    global mic_rms
    mic_rms = float(np.sqrt(np.mean(indata[:, 0] ** 2)))  # pro medidor de nível do app
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
        outdata[:len(chunk)] += chunk * sfx_gain
        sfx_pos = sfx_pos + frames if sfx_pos + frames < len(sfx) else None

def open_mic_bridge(mic_name=None, out_names=VIRTUAL_OUTS):
    devs = sd.query_devices()
    out = next((i for n in out_names for i, d in enumerate(devs) if n in d["name"] and d["max_output_channels"] >= 2), None)
    if out is None:
        print("Saída de áudio virtual não encontrada: o som do teleporte toca só aqui, a chamada não ouve.")
        return None
    virtual = lambda d: any(n in d["name"] for n in out_names)
    mic = next((i for i, d in enumerate(devs) if d["name"] == mic_name and d["max_input_channels"] > 0), None) if mic_name else None
    if mic is None:
        if mic_name:
            print(f"Microfone '{mic_name}' não encontrado: usando o padrão.")
        mic = sd.default.device[0]
        if mic < 0 or virtual(devs[mic]):  # sem entrada padrão, ou entrada do sistema já na saída virtual
            mic = next((i for i, d in enumerate(devs) if d["max_input_channels"] > 0 and not virtual(d)), None)
    if mic is None:
        print("Nenhum microfone encontrado: a câmera funciona, mas a chamada não recebe áudio deste script.")
        return None
    print(f"Microfone '{devs[mic]['name']}' + teleporte -> '{devs[out]['name']}'. Na chamada, escolha esse microfone.")
    streams = (sd.InputStream(device=mic, samplerate=SR, channels=1, dtype="float32", blocksize=BLOCK, callback=on_mic),
               sd.OutputStream(device=out, samplerate=SR, channels=2, dtype="float32", blocksize=BLOCK, callback=on_audio))
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

def is_teleport_sign(hand, face, reach=REACH):
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
    return np.linalg.norm((p[8] + p[12]) / 2 - forehead) < eyes * reach

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

def fire_sound():
    global sfx_pos
    subprocess.Popen(["afplay", SOUND])  # pra você ouvir
    sfx_pos = 0                          # pra chamada ouvir

class Teleporter:
    # estado do efeito (gesto, fundo, sumiço), o mesmo pro modo terminal e pro app
    def __init__(self, on_fire):
        self.seg = mp.solutions.selfie_segmentation.SelfieSegmentation(model_selection=1)
        self.hands = mp.solutions.hands.Hands(max_num_hands=2, model_complexity=1, min_detection_confidence=0.5)
        self.faces = mp.solutions.face_detection.FaceDetection(model_selection=1, min_detection_confidence=0.5)  # 1 = até ~5 m
        self.on_fire, self.reach = on_fire, REACH
        self.bg, self.bg_at = None, None
        self.hidden, self.fx_start, self.target = False, None, False
        self.sign_since, self.last_sign, self.armed = None, 0.0, True
        self.face, self.face_at = None, 0.0
        self.n_frame, self.sign, self.gesture_seen = 0, False, False

    def capture_bg(self, now, delay=BG_DELAY_S):
        self.bg_at = now + delay  # a sua sombra na parede também sai na foto: dá tempo de sair da luz

    def bg_countdown(self, now):
        return None if self.bg_at is None else max(0.0, self.bg_at - now)

    def reappear(self):
        self.hidden, self.fx_start = False, None

    def fire(self, now):
        if self.bg is None or self.fx_start is not None:
            return False
        self.on_fire()
        self.fx_start, self.target, self.armed = now + SOUND_LEAD, not self.hidden, False
        return True

    def step(self, frame, now):
        rgb = None  # convertido só quando algum modelo precisa, e uma vez por frame
        self.n_frame += 1
        if self.fx_start is not None:
            self.sign = False
        elif self.n_frame % 2 == 0:  # detecta a cada 2 frames: mão + rosto custam ~25 ms e travavam o vídeo
            self.sign = False
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            fr = self.faces.process(rgb)
            if fr.detections:
                self.face, self.face_at = fr.detections[0], now
            elif now - self.face_at > 1.0:
                self.face = None  # a mão na testa às vezes esconde o rosto: usa o último visto por 1 s
            hr = self.hands.process(rgb)
            if hr.multi_hand_landmarks and self.face is not None:
                self.sign = any(is_teleport_sign(h, self.face, self.reach) for h in hr.multi_hand_landmarks)
        if self.sign:
            self.last_sign = now
            self.sign_since = self.sign_since or now
        elif now - self.last_sign > 0.3:  # tolera uns frames perdidos no meio do gesto
            self.sign_since, self.armed = None, True
        if self.sign_since and self.armed and now - self.sign_since > HOLD_S:
            self.gesture_seen = True
            self.fire(now)

        p = None
        if self.fx_start is not None:
            t = (now - self.fx_start) / FX_S
            if t >= 1:
                self.hidden, self.fx_start = self.target, None
            elif t >= 0:
                p = t if self.target else 1 - t

        if p is not None:
            rgb = rgb if rgb is not None else cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            out = teleport(frame, self.bg, person_mask(self.seg, rgb), p)
        elif self.hidden:
            out = self.bg
        else:
            out = frame

        if self.bg_at is not None and now >= self.bg_at:
            self.bg, self.hidden, self.fx_start, self.bg_at = frame.copy(), False, None, None
        return out

def run_ipc():
    # modo app: frames entram e saem por memória compartilhada; comandos no stdin, eventos no stdout
    global sfx, sfx_gain
    proto, sys.stdout = sys.stdout, sys.stderr  # print() solto não pode sujar o protocolo
    say_lock = threading.Lock()  # a thread do stdin também emite: sem trava, linhas JSON podem se misturar

    def say(event, **f):
        with say_lock:
            emit(event, out=proto, **f)

    cmds = queue.Queue()

    def read_stdin():
        for line in sys.stdin:
            if line.strip():
                try:
                    cmds.put(parse_command(line))
                except ValueError as e:
                    say("error", code="bad_command", msg=str(e))
        cmds.put({"cmd": "stop"})  # o app fechou o pipe (ou morreu): encerra junto

    threading.Thread(target=read_stdin, daemon=True).start()
    say("ready", version=1)
    start = cmds.get()
    while start["cmd"] != "start":
        if start["cmd"] == "stop":
            return 0
        start = cmds.get()
    if not os.path.exists(SOUND):
        say("error", code="no_sound", msg="sons/teleport.wav não encontrado")
        return 1
    sfx, sfx_gain = load_sfx(), float(start.get("gain", SFX_GAIN))
    try:
        shm = FrameShm(start["shm"], W, H)
    except (KeyError, OSError, ValueError) as e:
        say("error", code="bad_shm", msg=str(e))
        return 1
    bridge = None  # guarda a referência: os fluxos de áudio vivem enquanto ela existir
    if start.get("mic") and not any(d["name"] == start["mic"] for d in sd.query_devices()):
        say("error", code="mic_not_found", msg=f"microfone '{start['mic']}' não encontrado: usando o padrão")
    if start.get("output", "") is not None:
        bridge = open_mic_bridge(start.get("mic"), (start["output"],) if start.get("output") else VIRTUAL_OUTS)
        if bridge is None:
            say("error", code="audio_unavailable", msg="sem saída virtual ou sem microfone")
    vcam = None
    if start.get("vcam", True):
        try:
            vcam = pyvirtualcam.Camera(W, H, fps=int(start.get("fps", 30)), fmt=pyvirtualcam.PixelFormat.BGR)
        except RuntimeError as e:
            say("error", code="no_virtual_camera", msg=str(e))
    tp = Teleporter(fire_sound)
    tp.reach = float(start.get("reach", REACH))
    next_state = next_level = t0 = time.time()
    frames, seen_sent = 0, False
    try:
        while True:
            now = time.time()
            try:
                c = cmds.get_nowait()
            except queue.Empty:
                c = None
            if c and c["cmd"] == "stop":
                break
            try:  # campo com valor errado vira erro pro app, não derruba o motor
                if not c: pass
                elif c["cmd"] == "capture_bg": tp.capture_bg(now, float(c.get("delay_s", BG_DELAY_S)))
                elif c["cmd"] == "toggle": tp.fire(now)
                elif c["cmd"] == "reappear": tp.reappear()
                elif c["cmd"] == "set":
                    sfx_gain = float(c.get("gain", sfx_gain))
                    tp.reach = float(c.get("reach", tp.reach))
                elif c["cmd"] == "test_sound": fire_sound()
            except (TypeError, ValueError) as e:
                say("error", code="bad_command", msg=f"{c['cmd']}: {e}")
            if now >= next_state:
                say("state", hidden=tp.hidden, bg_ready=tp.bg is not None, bg_countdown=tp.bg_countdown(now),
                    gesture=tp.sign, fps=round(frames / max(now - t0, 1e-6), 1))
                next_state, t0, frames = now + 0.2, now, 0
            if bridge and now >= next_level:
                say("mic_level", rms=round(mic_rms, 4))
                next_level = now + 0.1
            bgra = shm.read("in")
            if bgra is None:
                time.sleep(0.001)
                continue
            out = tp.step(cv2.cvtColor(bgra, cv2.COLOR_BGRA2BGR), now)
            shm.write("out", cv2.cvtColor(out, cv2.COLOR_BGR2BGRA))
            if vcam:
                vcam.send(out)
            frames += 1
            if tp.gesture_seen and not seen_sent:
                say("gesture_seen")
                seen_sent = True
    finally:
        if vcam:
            vcam.close()
        shm.close()
    return 0

def main():
    global sfx
    if not os.path.exists(SOUND):
        raise SystemExit("Som não encontrado: rode ./setup.sh (ou tools/preparar_som.py) antes.")
    sfx = load_sfx()
    tp = Teleporter(fire_sound)
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
            out = tp.step(frame, now)
            cam.send(out)  # sem espelhar: a própria chamada espelha a sua prévia

            preview = cv2.flip(out, 1)
            if tp.bg_at is not None:
                cv2.putText(preview, f"Fundo em {tp.bg_countdown(now):.0f}s: saia do quadro e da frente da luz", (30, 60),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 255), 3)
            elif tp.bg is None:
                cv2.putText(preview, "Aperte B pra gravar o fundo", (30, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
            if tp.sign:
                cv2.circle(preview, (40, H - 40), 18, (0, 255, 0), -1)  # gesto reconhecido (só na prévia)
            cv2.imshow("teleporte", preview)
            k = cv2.waitKey(1) & 0xFF
            if k == ord('b'): tp.capture_bg(now)
            elif k == ord('r'): tp.reappear()
            elif k == ord('q'): break

if __name__ == "__main__":
    sys.exit(run_ipc() if "--ipc" in sys.argv[1:] else main())
