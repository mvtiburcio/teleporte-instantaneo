# app.py — janela principal do Ilusio para Windows: barra lateral + páginas, tema seguindo o sistema
from PySide6.QtCore import QSettings, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QHBoxLayout, QListWidget, QMainWindow, QStackedWidget, QWidget

from . import theme
from .devices import list_cameras, pick_default
from .home import HomePage
from .worker import EngineWorker


class MainWindow(QMainWindow):
    def __init__(self, cameras=None):
        super().__init__()
        self.setWindowTitle("Ilusio")
        self.resize(1040, 700)
        self.setMinimumSize(900, 620)
        self.settings = QSettings("Ilusio", "Ilusio")
        self.cameras = list_cameras() if cameras is None else cameras
        default = pick_default(self.cameras, self.settings.value("camera"))

        self.nav = QListWidget()
        self.nav.setObjectName("nav")
        self.nav.setFixedWidth(190)
        self.nav.addItem("▶   Início")  # as outras abas chegam no PR 3
        self.home = HomePage(self.cameras)
        if default:
            self.home.camera.setCurrentIndex(self.cameras.index(default))
        self.pages = QStackedWidget()
        self.pages.addWidget(self.home)
        self.nav.currentRowChanged.connect(self.pages.setCurrentIndex)
        self.nav.setCurrentRow(0)

        root = QWidget()
        layout = QHBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self.nav)
        layout.addWidget(self.pages, 1)
        self.setCentralWidget(root)

        self.worker = EngineWorker()
        self.worker.frame.connect(self.home.preview.set_frame)
        self.worker.state.connect(self._on_state)
        self.worker.failed.connect(self.home.error.setText)
        self.worker.stopped.connect(self._on_stopped)
        self._restart = False  # trocou de câmera ligado: religa quando o motor terminar de parar
        self.home.power_clicked.connect(self._toggle_power)
        self.home.background_clicked.connect(lambda: self.worker.send("capture_bg"))
        self.home.toggle_clicked.connect(lambda: self.worker.send("toggle"))
        self.home.camera_changed.connect(self._camera_changed)

        hints = QGuiApplication.styleHints()
        hints.colorSchemeChanged.connect(self._apply_theme)
        self._apply_theme(hints.colorScheme())

    def _apply_theme(self, scheme):
        self.setStyleSheet(theme.stylesheet("dark" if scheme == Qt.ColorScheme.Dark else "light"))

    def _toggle_power(self):
        if self.worker.running:
            self.worker.stop()
            return
        self._start()

    def _start(self):
        self.home.error.setText("")
        camera = self.cameras[self.home.camera.currentIndex()]
        self.worker.start(camera.index, fps=int(self.settings.value("fps", 30)))
        self.home.set_running(True)

    def _on_stopped(self):
        self.home.set_running(False)
        if self._restart:
            self._restart = False
            self._start()

    def _camera_changed(self, i):
        if 0 <= i < len(self.cameras):
            self.settings.setValue("camera", self.cameras[i].name)
            if self.worker.running:  # troca ao vivo: para e religa com a câmera nova
                self._restart = True
                self.worker.stop()

    def _on_state(self, state):
        self.home.preview.set_status(state)
        self.home.set_running(True, state)

    def closeEvent(self, event):
        self.worker.stop()
        super().closeEvent(event)
