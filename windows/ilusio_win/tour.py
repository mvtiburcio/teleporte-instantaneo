# tour.py — tour da primeira abertura (mesma opção B do Mac): ilustração à esquerda, texto e passos à direita
from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

PAGES = [
    ("Bem-vindo ao Ilusio", "Efeitos mágicos para a sua videochamada. O primeiro é o Teletransporte Instantâneo: suma da "
     "chamada com um gesto, com som e tudo. Este tour leva um minuto.", "✨", "#FF8A1F", "#E84393"),
    ("Como funciona", "O Ilusio usa a sua câmera, aplica o efeito e entrega uma câmera e um microfone virtuais. Na "
     "chamada (Meet, Zoom, Teams ou WhatsApp), você escolhe esses dois no lugar dos normais.", "🎥", "#3C6BFF", "#7B4DFF"),
    ("O gesto", "Encoste o indicador e o médio na testa e segure meio segundo. Você some com o som; repita para "
     "voltar. Sem a mão livre? Use o atalho Ctrl+Alt+Shift+T.", "✌️", "#2ECC71", "#16A085"),
    ("Vamos preparar", "Um checklist guia você em uns 5 minutos: câmera, microfone, câmera e som virtuais, o fundo e "
     "um teste. Cada item fica verde sozinho quando estiver certo.", "✅", "#FF8A1F", "#F1C40F"),
]


class Tour(QWidget):
    finished = Signal(bool)  # True = abrir o checklist

    def __init__(self):
        super().__init__()
        self.step = 0
        self.art = QLabel()
        self.art.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.counter = QLabel()
        self.counter.setObjectName("muted")
        self.title = QLabel()
        self.title.setStyleSheet("font-size: 24pt; font-weight: 700; background: transparent;")
        self.text = QLabel()
        self.text.setWordWrap(True)
        self.text.setStyleSheet("font-size: 12pt; background: transparent;")
        self.steps = QLabel()
        self.steps.setStyleSheet("background: transparent; line-height: 160%;")
        skip = QPushButton("Pular")
        skip.setFlat(True)
        skip.clicked.connect(lambda: self.finish(open_setup=False))
        self.back = QPushButton("Voltar")
        self.back.clicked.connect(lambda: self._go(-1))
        self.next = QPushButton()
        self.next.setObjectName("primary")
        self.next.clicked.connect(self._next)

        buttons = QHBoxLayout()
        buttons.addWidget(skip)
        buttons.addStretch()
        buttons.addWidget(self.back)
        buttons.addWidget(self.next)
        right = QVBoxLayout()
        right.setContentsMargins(40, 40, 40, 32)
        for w in (self.counter, self.title, self.text, self.steps):
            right.addWidget(w)
        right.addStretch()
        right.addLayout(buttons)
        side = QWidget()
        side.setFixedWidth(460)
        side.setLayout(right)
        row = QHBoxLayout(self)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(0)
        row.addWidget(self.art, 1)
        row.addWidget(side)
        self._render()

    def _go(self, delta):
        self.step = max(0, min(len(PAGES) - 1, self.step + delta))
        self._render()

    def _next(self):
        if self.step == len(PAGES) - 1:
            self.finish(open_setup=True)
        else:
            self._go(1)

    def finish(self, open_setup):
        self.finished.emit(open_setup)

    def _render(self):
        title, text, symbol, c1, c2 = PAGES[self.step]
        self.art.setText(f"<span style='font-size:110pt'>{symbol}</span>")
        self.art.setStyleSheet(f"background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 {c1}, stop:1 {c2});")
        self.counter.setText(f"Passo {self.step + 1} de {len(PAGES)}")
        self.title.setText(title)
        self.text.setText(text)
        marks = ["✓" if i < self.step else ("●" if i == self.step else "○") for i in range(len(PAGES))]
        self.steps.setText("<br>".join(f"{m}&nbsp;&nbsp;{p[0]}" for m, p in zip(marks, PAGES)))
        self.back.setVisible(self.step > 0)
        self.next.setText("Abrir o checklist" if self.step == len(PAGES) - 1 else "Continuar")
