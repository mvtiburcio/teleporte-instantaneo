# home.py — aba Início: prévia com status por cima, câmera escolhida, Ligar / Gravar fundo / Some-Volta
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QPixmap
from PySide6.QtWidgets import QComboBox, QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

from .theme import GREEN


def dot(on):
    # bolinha verde quando o status está ativo, cinza quando não (como no Mac)
    return f"<span style='color:{GREEN if on else '#8A8A92'}'>●</span>&nbsp;&nbsp;"


class Preview(QLabel):
    """Prévia 16:9 com as cápsulas de status e a instrução do fundo por cima."""

    def __init__(self):
        super().__init__()
        self.setObjectName("preview")
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setMinimumSize(480, 270)
        self.setText("Ligue o Ilusio para ver a prévia")
        self._pixmap = None
        self.live = self._chip()
        self.background = self._chip()
        self.fps = self._chip()
        self.guide = QLabel(self)
        self.guide.setObjectName("guide")
        self.guide.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.guide.hide()
        self.set_status(None)

    def _chip(self):
        chip = QLabel(self)
        chip.setObjectName("chip")
        return chip

    def set_status(self, state):
        on = state is not None
        self.live.setText(dot(on) + ("Ao vivo" if on else "Desligado"))
        self.background.setVisible(on)
        ready = bool(on and state["bg_ready"])
        self.background.setText(dot(ready) + ("Fundo pronto" if ready else "Sem fundo"))
        self.fps.setVisible(on)
        self.fps.setText(f"{state['fps']:.0f} fps" if on else "")
        self.setProperty("gesture", bool(on and state["gesture"]))
        self.style().unpolish(self)
        self.style().polish(self)
        countdown = state and state["bg_countdown"]
        if countdown is not None and countdown is not False:
            self.guide.setText(f"<div style='font-size:44pt;font-weight:700'>{int(countdown) + 1}</div>"
                               "<div style='font-size:16pt;font-weight:700'>Saia do quadro</div>"
                               "<div>e da frente da luz, pra sua sombra não ficar no fundo</div>")
            self.guide.show()
        else:
            self.guide.hide()
        self._layout_overlays()

    def set_frame(self, image):
        self._pixmap = QPixmap.fromImage(image)
        self._show_pixmap()

    def clear(self):
        self._pixmap = None
        self.setPixmap(QPixmap())
        self.setText("Ligue o Ilusio para ver a prévia")

    def _show_pixmap(self):
        if self._pixmap:
            self.setPixmap(self._pixmap.scaled(self.size(), Qt.AspectRatioMode.KeepAspectRatio,
                                               Qt.TransformationMode.SmoothTransformation))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._show_pixmap()
        self._layout_overlays()

    def _layout_overlays(self):
        for chip in (self.live, self.background, self.fps, self.guide):
            chip.adjustSize()
        self.live.move(12, 12)
        self.background.move(self.live.x() + self.live.width() + 8, 12)
        self.fps.move(self.width() - self.fps.width() - 12, 12)
        self.guide.move((self.width() - self.guide.width()) // 2, (self.height() - self.guide.height()) // 2)


class HomePage(QWidget):
    power_clicked = Signal()
    background_clicked = Signal()
    toggle_clicked = Signal()
    camera_changed = Signal(int)  # índice na lista de câmeras

    def __init__(self, cameras):
        super().__init__()
        self.preview = Preview()
        self.camera = QComboBox()
        for c in cameras:
            self.camera.addItem(f"📷  {c.name}")
        self.camera.currentIndexChanged.connect(self.camera_changed)
        self.power = QPushButton("Ligar o Ilusio")
        self.power.setObjectName("primary")
        self.power.setEnabled(bool(cameras))
        self.power.clicked.connect(self.power_clicked)
        self.bg = QPushButton("Gravar fundo")
        self.bg.clicked.connect(self.background_clicked)
        self.toggle = QPushButton("Some / Volta")
        self.toggle.clicked.connect(self.toggle_clicked)
        self.error = QLabel()
        self.error.setObjectName("error")
        self.error.setWordWrap(True)
        if not cameras:
            self.error.setText("Nenhuma câmera encontrada: conecte uma webcam e abra o Ilusio de novo.")

        buttons = QHBoxLayout()
        buttons.addStretch()
        for b in (self.power, self.bg, self.toggle):
            buttons.addWidget(b)
        buttons.addStretch()
        top = QHBoxLayout()
        top.addWidget(self.camera)
        top.addStretch()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 16, 20, 16)
        layout.addLayout(top)
        layout.addWidget(self.preview, 1)
        layout.addLayout(buttons)
        layout.addWidget(self.error)
        self.set_running(False)

    def set_running(self, running, state=None):
        self.power.setText("Desligar" if running else "Ligar o Ilusio")
        self.bg.setEnabled(running)
        self.toggle.setEnabled(bool(running and state and state["bg_ready"]))
        if state:
            self.bg.setText("Regravar fundo" if state["bg_ready"] else "Gravar fundo")
        if not running:
            self.preview.clear()
            self.preview.set_status(None)
