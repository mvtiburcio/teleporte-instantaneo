# setup.py — aba Configuração: checklist de 7 itens que se confere sozinho (o 7º é marcado à mão)
from dataclasses import dataclass, fields

from PySide6.QtCore import Qt, QUrl, Signal
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QComboBox, QFrame, QHBoxLayout, QLabel, QProgressBar, QPushButton, QScrollArea, QVBoxLayout, QWidget

from .theme import ACCENT, GREEN

ITEMS = ["camera", "mic", "virtual_camera", "virtual_audio", "background", "gesture", "call_app"]
VIRTUAL_CAMERAS = ("Ilusio Camera", "OBS Virtual Camera")
VIRTUAL_OUTPUTS = ("Ilusio Mic", "CABLE Input")


@dataclass
class Checks:
    camera: bool = False
    mic: bool = False
    virtual_camera: bool = False
    virtual_audio: bool = False
    background: bool = False
    gesture: bool = False
    call_app: bool = False

    @property
    def done(self):
        return sum(getattr(self, f.name) for f in fields(self))

    @property
    def first_pending(self):
        return next((item for item in ITEMS if not getattr(self, item)), None)

    @staticmethod
    def current(background, gesture, call_app):
        import sounddevice as sd
        from cv2_enumerate_cameras import enumerate_cameras
        from .devices import backend, list_mics
        names = [c.name for c in enumerate_cameras(backend())]
        outputs = [d["name"] for d in sd.query_devices() if d["max_output_channels"] > 0]
        return Checks(
            camera=any(not any(v in n for v in VIRTUAL_CAMERAS) for n in names),
            mic=bool(list_mics()),
            virtual_camera=any(any(v in n for v in VIRTUAL_CAMERAS) for n in names),
            virtual_audio=any(any(v in n for v in VIRTUAL_OUTPUTS) for n in outputs),
            background=background, gesture=gesture, call_app=call_app)


CALL_APPS = {
    "Meet": ["Na chamada, ⋮ ▸ Configurações.", "Vídeo: câmera Ilusio Camera (ou OBS Virtual Camera).",
             "Áudio: microfone CABLE Output (VB-Audio Virtual Cable) e cancelamento de ruído desligado."],
    "Zoom": ["Configurações ▸ Vídeo: câmera Ilusio Camera (ou OBS Virtual Camera).",
             "Áudio: microfone CABLE Output e supressão de ruído em Baixa."],
    "Teams": ["Configurações ▸ Dispositivos: câmera Ilusio Camera e microfone CABLE Output.",
              "Desligue a supressão de ruído."],
    "WhatsApp": ["Na chamada de vídeo, ⌄ ao lado da câmera: Ilusio Camera.",
                 "⌄ ao lado do microfone: CABLE Output (se não aparecer, deixe o padrão e escolha CABLE Output como "
                 "microfone padrão em Configurações ▸ Sistema ▸ Som)."],
}


class SetupPage(QWidget):
    go_home = Signal()
    call_app_done = Signal()

    TITLES = {
        "camera": ("Câmera", "Uma webcam ligada e liberada pro Ilusio."),
        "mic": ("Microfone", "Um microfone ligado e liberado pro Ilusio."),
        "virtual_camera": ("Câmera virtual", "Entrega o vídeo com o efeito pra chamada."),
        "virtual_audio": ("Som virtual (VB-Cable)", "Entrega a sua voz + o som do efeito pra chamada."),
        "background": ("Gravar o fundo", "A imagem que aparece quando você some."),
        "gesture": ("Testar o gesto", "Dois dedos na testa até ouvir o som."),
        "call_app": ("Escolher no app de chamada", "Câmera virtual e microfone CABLE Output."),
    }
    GUIDES = {
        "camera": ["Conecte a webcam.", "Em Configurações ▸ Privacidade ▸ Câmera, deixe ligado \"Permitir que apps da "
                   "área de trabalho acessem a câmera\"."],
        "mic": ["Em Configurações ▸ Privacidade ▸ Microfone, deixe ligado \"Permitir que apps da área de trabalho "
                "acessem o microfone\"."],
        "virtual_camera": ["Instale o OBS Studio (grátis): ele fornece a câmera virtual.",
                           "Abra o OBS uma vez e clique em Iniciar câmera virtual; depois, feche o OBS.",
                           "Volte aqui: este item fica verde sozinho."],
        "virtual_audio": ["Baixe o VB-Cable (grátis) e extraia o .zip.",
                          "Clique com o botão direito em VBCABLE_Setup_x64.exe ▸ Executar como administrador ▸ Install.",
                          "Reinicie o computador."],
        "background": ["No Início, clique em Ligar o Ilusio e depois em Gravar fundo.",
                       "Saia do quadro e da frente da luz durante a contagem."],
        "gesture": ["Encoste o indicador e o médio na testa e segure meio segundo.",
                    "Repita pra voltar. Também dá pelo atalho Ctrl+Alt+Shift+T."],
    }

    def __init__(self):
        super().__init__()
        self.header = QLabel()
        self.header.setStyleSheet("font-size: 20pt; font-weight: 700; background: transparent;")
        self.subtitle = QLabel()
        self.subtitle.setObjectName("muted")
        self.progress = QProgressBar()
        self.progress.setRange(0, len(ITEMS))
        self.progress.setTextVisible(False)
        self.progress.setFixedHeight(6)
        self.progress.setStyleSheet(f"QProgressBar::chunk {{ background: {ACCENT}; border-radius: 3px; }}")
        self.rows = QVBoxLayout()
        self.rows.setSpacing(8)
        body = QWidget()
        inner = QVBoxLayout(body)
        inner.setContentsMargins(32, 24, 32, 24)
        for w in (self.header, self.subtitle, self.progress):
            inner.addWidget(w)
        inner.addSpacing(8)
        inner.addLayout(self.rows)
        inner.addStretch()
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setWidget(body)
        QVBoxLayout(self).addWidget(scroll)
        self.app_choice = "Meet"
        self.checks = None

    def refresh(self, checks):
        if checks == self.checks:
            return
        self.checks = checks
        done = checks.done
        self.header.setText("Tudo pronto! 🎉" if done == len(ITEMS) else "Vamos deixar tudo pronto")
        self.subtitle.setText("Na chamada, faça o gesto e suma." if done == len(ITEMS)
                              else f"{done} de {len(ITEMS)} · cada item fica verde sozinho quando estiver certo.")
        self.progress.setValue(done)
        while self.rows.count():
            self.rows.takeAt(0).widget().deleteLater()
        for i, item in enumerate(ITEMS):
            self.rows.addWidget(self._row(i, item, getattr(checks, item), item == checks.first_pending))

    def _row(self, i, item, ok, current):
        card = QFrame()
        card.setObjectName("card")
        card.setStyleSheet(f"#card {{ border-radius: 8px; border: 1px solid {ACCENT if current else 'rgba(128,128,128,60)'}; }}")
        badge = QLabel("✓" if ok else str(i + 1))
        badge.setFixedSize(26, 26)
        badge.setAlignment(Qt.AlignmentFlag.AlignCenter)
        badge.setStyleSheet(f"border-radius: 13px; font-weight: 700; color: white; background: {GREEN}" if ok
                            else "border-radius: 13px; font-weight: 700; border: 2px solid #8A8A92; background: transparent")
        title, subtitle = self.TITLES[item]
        text = QVBoxLayout()
        name = QLabel(f"<b>{title}</b>")
        name.setStyleSheet("background: transparent;")
        text.addWidget(name)
        detail = QLabel("Pronto." if ok else subtitle)
        detail.setObjectName("muted")
        text.addWidget(detail)
        row = QHBoxLayout()
        row.addWidget(badge)
        row.addSpacing(8)
        row.addLayout(text, 1)
        if not ok:
            label, run = self._action(item)
            button = QPushButton(label)
            if current:
                button.setObjectName("primary")
            button.clicked.connect(run)
            row.addWidget(button)
        layout = QVBoxLayout(card)
        layout.addLayout(row)
        if current and not ok:
            layout.addWidget(self._guide(item))
        return card

    def _action(self, item):
        url = lambda u: (lambda: QDesktopServices.openUrl(QUrl(u)))
        return {
            "camera": ("Abrir privacidade", url("ms-settings:privacy-webcam")),
            "mic": ("Abrir privacidade", url("ms-settings:privacy-microphone")),
            "virtual_camera": ("Baixar o OBS", url("https://obsproject.com/download")),
            "virtual_audio": ("Baixar o VB-Cable", url("https://vb-audio.com/Cable/")),
            "background": ("Ir para o Início", self.go_home.emit),
            "gesture": ("Ir para o Início", self.go_home.emit),
            "call_app": ("Já escolhi", self.call_app_done.emit),
        }[item]

    def _guide(self, item):
        box = QWidget()
        layout = QVBoxLayout(box)
        layout.setContentsMargins(42, 4, 0, 0)
        if item == "call_app":
            apps = QComboBox()
            apps.addItems(list(CALL_APPS))
            apps.setCurrentText(self.app_choice)
            steps = QLabel()
            steps.setWordWrap(True)
            steps.setObjectName("muted")
            show = lambda name: (setattr(self, "app_choice", name), steps.setText(numbered(CALL_APPS[name])))
            apps.currentTextChanged.connect(show)
            show(self.app_choice)
            layout.addWidget(apps, alignment=Qt.AlignmentFlag.AlignLeft)
            layout.addWidget(steps)
        else:
            steps = QLabel(numbered(self.GUIDES[item]))
            steps.setWordWrap(True)
            steps.setObjectName("muted")
            layout.addWidget(steps)
        return box


def numbered(lines):
    return "<br>".join(f"{i}. {line}" for i, line in enumerate(lines, 1))
