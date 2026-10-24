# app.py — janela principal do Ilusio para Windows: barra lateral + páginas, tema seguindo o sistema
from PySide6.QtCore import QSettings, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QHBoxLayout, QListWidget, QMainWindow, QStackedWidget, QWidget

from . import theme
from .devices import list_cameras, list_mics, pick_default
from .home import HomePage
from .pages import DevicesPage, SettingsPage, SupportPage
from .worker import EngineWorker


class MainWindow(QMainWindow):
    def __init__(self, cameras=None, mics=None):
        super().__init__()
        self.setWindowTitle("Ilusio")
        self.resize(1040, 700)
        self.setMinimumSize(900, 620)
        self.settings = QSettings(QSettings.defaultFormat(), QSettings.Scope.UserScope, "Ilusio", "Ilusio")
        self.cameras = list_cameras() if cameras is None else cameras
        default = pick_default(self.cameras, self.settings.value("camera"))

        self.nav = QListWidget()
        self.nav.setObjectName("nav")
        self.nav.setFixedWidth(190)
        s = self.settings
        self.home = HomePage(self.cameras)
        if default:
            self.home.camera.setCurrentIndex(self.cameras.index(default))
        self.devices = DevicesPage(list_mics() if mics is None else mics, s.value("mic", ""), int(s.value("fps", 30)),
                                   float(s.value("gain", 0.8)), float(s.value("reach", 1.5)))
        self.support = SupportPage()
        self.settings_page = SettingsPage(s.value("theme", "system"))
        self.pages = QStackedWidget()
        for icon, label, page in (("▶", "Início", self.home), ("🎙", "Câmera e mic", self.devices),
                                  ("♡", "Apoiar", self.support), ("⚙", "Ajustes", self.settings_page)):
            self.nav.addItem(f"{icon}   {label}")
            self.pages.addWidget(page)
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
        self.worker.stopped.connect(lambda: self.devices.set_running(False))
        self._restart = False  # trocou de câmera ligado: religa quando o motor terminar de parar
        self.home.power_clicked.connect(self._toggle_power)
        self.home.background_clicked.connect(lambda: self.worker.send("capture_bg"))
        self.home.toggle_clicked.connect(lambda: self.worker.send("toggle"))
        self.home.camera_changed.connect(self._camera_changed)
        self.devices.mic_changed.connect(lambda name: self._save_and_restart("mic", name))
        self.devices.fps_changed.connect(lambda fps: self._save_and_restart("fps", fps))
        self.devices.gain_changed.connect(lambda v: self._save_and_set("gain", v))
        self.devices.reach_changed.connect(lambda v: self._save_and_set("reach", v))
        self.devices.test_sound.connect(lambda: self.worker.send("test_sound"))
        self.settings_page.theme_changed.connect(self._theme_chosen)

        hints = QGuiApplication.styleHints()
        hints.colorSchemeChanged.connect(self._apply_theme)
        self._apply_theme(hints.colorScheme())

    def _apply_theme(self, scheme=None):
        chosen = self.settings.value("theme", "system")
        if chosen == "system":
            scheme = QGuiApplication.styleHints().colorScheme() if scheme is None else scheme
            chosen = "dark" if scheme == Qt.ColorScheme.Dark else "light"
        self.setStyleSheet(theme.stylesheet(chosen))

    def _theme_chosen(self, value):
        self.settings.setValue("theme", value)
        self._apply_theme()

    def _save_and_set(self, key, value):  # volume e sensibilidade valem na hora
        self.settings.setValue(key, value)
        self.worker.send("set", **{key: value})

    def _save_and_restart(self, key, value):  # microfone e fps são abertos ao ligar: religa se estiver ligado
        self.settings.setValue(key, value)
        if self.worker.running:
            self._restart = True
            self.worker.stop()

    def _toggle_power(self):
        if self.worker.running:
            self.worker.stop()
            return
        self._start()

    def _start(self):
        self.home.error.setText("")
        camera = self.cameras[self.home.camera.currentIndex()]
        s = self.settings
        self.worker.start(camera.index, fps=int(s.value("fps", 30)), gain=float(s.value("gain", 0.8)),
                          reach=float(s.value("reach", 1.5)), mic=s.value("mic", "") or None)
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
        self.devices.set_running(True, state["rms"])

    def closeEvent(self, event):
        self.worker.stop()
        super().closeEvent(event)
