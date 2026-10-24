# pages.py — abas Câmera e mic, Apoiar e Ajustes
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QGuiApplication, QPixmap
from PySide6.QtWidgets import (QComboBox, QFormLayout, QHBoxLayout, QLabel, QProgressBar, QPushButton, QSlider,
                               QVBoxLayout, QWidget)

from . import __version__, hotkeys, pix
from .worker import to_qimage


def title(text):
    label = QLabel(text)
    label.setStyleSheet("font-size: 20pt; font-weight: 700; background: transparent;")
    return label


def muted(text):
    label = QLabel(text)
    label.setObjectName("muted")
    label.setWordWrap(True)
    return label


class DevicesPage(QWidget):
    mic_changed = Signal(str)       # "" = padrão do sistema
    fps_changed = Signal(int)
    gain_changed = Signal(float)
    reach_changed = Signal(float)
    test_sound = Signal()

    def __init__(self, mics, mic, fps, gain, reach):
        super().__init__()
        self.mic = QComboBox()
        self.mic.addItem("Padrão do sistema", "")
        for name in mics:
            self.mic.addItem(name, name)
        self.mic.setCurrentIndex(max(self.mic.findData(mic or ""), 0))
        self.mic.currentIndexChanged.connect(lambda: self.mic_changed.emit(self.mic.currentData()))
        self.level = QProgressBar()
        self.level.setRange(0, 100)
        self.level.setTextVisible(False)
        self.level.setFixedHeight(8)
        self.test = QPushButton("Testar o som")
        self.test.setEnabled(False)
        self.test.clicked.connect(self.test_sound)
        self.fps = QComboBox()
        for value in (15, 30, 60):
            self.fps.addItem(f"{value} fps", value)
        self.fps.setCurrentIndex(max(self.fps.findData(fps), 0))
        self.fps.currentIndexChanged.connect(lambda: self.fps_changed.emit(self.fps.currentData()))
        self.gain = self._slider(0, 150, int(gain * 100), lambda v: self.gain_changed.emit(v / 100))
        self.reach = self._slider(100, 250, int(reach * 100), lambda v: self.reach_changed.emit(v / 100))

        form = QFormLayout()
        form.setHorizontalSpacing(24)
        form.setVerticalSpacing(12)
        form.addRow("Microfone", self.mic)
        form.addRow("Nível", self.level)
        form.addRow("Som do efeito", self.test)
        form.addRow("Taxa de quadros", self.fps)
        form.addRow("Volume do efeito", self.gain)
        form.addRow("Sensibilidade do gesto", self.reach)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(32, 24, 32, 24)
        layout.addWidget(title("Câmera e mic"))
        layout.addWidget(muted("A câmera fica no Início. Aqui, o microfone que vai pra chamada junto com o som do "
                               "efeito, a fluidez do vídeo e os ajustes finos."))
        layout.addSpacing(12)
        layout.addLayout(form)
        layout.addWidget(muted("60 fps deixa o movimento mais fluido e usa mais processador; se a câmera não aguentar, "
                               "ela entrega o máximo que tem. Sensibilidade maior reconhece o gesto mais longe da testa."))
        layout.addStretch()

    @staticmethod
    def _slider(low, high, value, on_change):
        slider = QSlider(Qt.Orientation.Horizontal)
        slider.setRange(low, high)
        slider.setValue(value)
        slider.valueChanged.connect(on_change)
        return slider

    def set_running(self, running, rms=0.0):
        self.test.setEnabled(running)
        self.level.setValue(min(int((rms ** 0.5) * 250), 100) if running else 0)  # raiz: a fala aparece na barra


class SupportPage(QWidget):
    def __init__(self):
        super().__init__()
        qr = QLabel()
        qr.setPixmap(QPixmap.fromImage(to_qimage(pix.qr_bgr(pix.ILUSIO))).scaledToWidth(240))
        qr.setStyleSheet("background: white; border-radius: 12px; padding: 12px;")
        qr.setFixedSize(264, 264)
        self.copy = QPushButton("Copiar Pix copia-e-cola")
        self.copy.setObjectName("primary")
        self.copy.clicked.connect(self._copy)
        text = QVBoxLayout()
        text.addWidget(title("Curtiu o Ilusio? 💛"))
        text.addWidget(muted("O Ilusio é grátis e de código aberto. Se ele te fez rir numa reunião, um Pix de qualquer "
                             "valor ajuda a manter o projeto."))
        text.addSpacing(8)
        text.addWidget(self.copy, alignment=Qt.AlignmentFlag.AlignLeft)
        text.addWidget(muted("No app do banco: Pix ▸ Ler QR code ou Pix copia e cola, e digite o valor que quiser."))
        text.addStretch()
        row = QHBoxLayout(self)
        row.setContentsMargins(32, 32, 32, 32)
        row.addLayout(text, 1)
        row.addSpacing(24)
        row.addWidget(qr, alignment=Qt.AlignmentFlag.AlignTop)

    def _copy(self):
        QGuiApplication.clipboard().setText(pix.ILUSIO)
        self.copy.setText("Copiado! Obrigado 💛")


class KeyButton(QPushButton):
    """Campo que grava a próxima combinação pressionada (Esc cancela)."""
    recorded = Signal(object)
    recording = Signal(bool)

    def __init__(self, combo):
        super().__init__(str(combo))
        self.combo = combo
        self.active = False
        self.setMinimumWidth(200)
        self.clicked.connect(self.start)

    def start(self):
        self.active = True
        self.setText("Pressione a combinação…")
        self.recording.emit(True)

    def stop(self, combo=None):
        self.active = False
        if combo:
            self.combo = combo
        self.setText(str(self.combo))
        self.recording.emit(False)

    def keyPressEvent(self, event):
        if not self.active:
            return super().keyPressEvent(event)
        if event.key() == Qt.Key.Key_Escape:
            self.stop()
            return
        combo = hotkeys.from_key_event(event)
        if combo:
            self.recorded.emit(combo)


class ShortcutsPage(QWidget):
    changed = Signal(str, object)  # ação, Combo
    reset = Signal()
    recording = Signal(bool)

    def __init__(self, combos):
        super().__init__()
        self.buttons, self.errors = {}, {}
        form = QFormLayout()
        form.setHorizontalSpacing(24)
        form.setVerticalSpacing(10)
        for action, label in hotkeys.ACTIONS.items():
            button = KeyButton(combos[action])
            button.recorded.connect(lambda combo, a=action: self.changed.emit(a, combo))
            button.recording.connect(self.recording)
            error = muted("")
            error.setObjectName("error")
            self.buttons[action], self.errors[action] = button, error
            column = QVBoxLayout()
            column.addWidget(button)
            column.addWidget(error)
            form.addRow(label, column)
        restore = QPushButton("Restaurar padrões")
        restore.clicked.connect(self.reset)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(32, 24, 32, 24)
        layout.addWidget(title("Atalhos"))
        layout.addWidget(muted("Funcionam em qualquer app, inclusive com a chamada em primeiro plano. Use Ctrl ou Alt na "
                               "combinação; clique no atalho e pressione a nova combinação (Esc cancela)."))
        layout.addSpacing(12)
        layout.addLayout(form)
        layout.addWidget(restore, alignment=Qt.AlignmentFlag.AlignLeft)
        layout.addStretch()

    def show_result(self, action, combo, error):
        self.buttons[action].stop(None if error else combo)
        self.errors[action].setText(error or "")


class SettingsPage(QWidget):
    theme_changed = Signal(str)  # system, light, dark
    replay_tour = Signal()

    THEMES = [("Sistema", "system"), ("Claro", "light"), ("Escuro", "dark")]

    def __init__(self, theme):
        super().__init__()
        self.theme = QComboBox()
        for label, value in self.THEMES:
            self.theme.addItem(label, value)
        self.theme.setCurrentIndex(max(self.theme.findData(theme), 0))
        self.theme.currentIndexChanged.connect(lambda: self.theme_changed.emit(self.theme.currentData()))
        form = QFormLayout()
        form.setHorizontalSpacing(24)
        form.addRow("Tema", self.theme)
        tour = QPushButton("Rever o tour")
        tour.clicked.connect(self.replay_tour)
        form.addRow("Tour de boas-vindas", tour)
        form.addRow("Versão", QLabel(__version__))
        layout = QVBoxLayout(self)
        layout.setContentsMargins(32, 24, 32, 24)
        layout.addWidget(title("Ajustes"))
        layout.addSpacing(12)
        layout.addLayout(form)
        layout.addStretch()
