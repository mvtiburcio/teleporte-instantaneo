# preparar_som.py — converte qualquer áudio (mp3, m4a, wav...) no WAV que o teleporte usa,
# cortando o silêncio do começo pra o som sair junto com o gesto.
# uso: python tools/preparar_som.py [entrada] [saída]
import os, shutil, subprocess, sys, tempfile, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRE_ROLL = 0.1   # deixa 0,1 s antes do som: casa com SOUND_LEAD do teleporte.py
TAIL = 0.1       # e 0,1 s depois do último trecho audível
THRESHOLD = 0.02 # o que fica abaixo de 2% do volume máximo conta como silêncio

def decoder(src, dst):
    # afconvert vem com o macOS; no Windows (e no CI), o ffmpeg
    if shutil.which("afconvert"):
        return ["afconvert", "-f", "WAVE", "-d", "LEI16", src, dst]
    if shutil.which("ffmpeg"):
        return ["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-acodec", "pcm_s16le", dst]
    sys.exit("Precisa do afconvert (macOS) ou do ffmpeg (Windows: winget install ffmpeg) para converter o som.")

def prepare(src, dst):
    with tempfile.TemporaryDirectory() as tmp:
        tmp_wav = os.path.join(tmp, "som.wav")
        subprocess.run(decoder(src, tmp_wav), check=True)
        with wave.open(tmp_wav) as w:
            params, sr, ch = w.getparams(), w.getframerate(), w.getnchannels()
            a = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, ch)
    loud = np.nonzero(np.abs(a).max(1) > 32768 * THRESHOLD)[0]
    if not len(loud):
        sys.exit("O áudio está mudo.")
    start = max(loud[0] - int(PRE_ROLL * sr), 0)
    end = min(loud[-1] + int(TAIL * sr), len(a))
    with wave.open(dst, "wb") as out:
        out.setparams(params)
        out.writeframes(a[start:end].tobytes())
    print(f"{dst}: {(end - start) / sr:.2f} s (cortados {start / sr:.2f} s de silêncio no começo)")

if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "sons", "goku-teleport.mp3")
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "sons", "teleport.wav")
    prepare(src, dst)
