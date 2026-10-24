# app.py — janela principal do Ilusio para Windows: barra lateral + páginas, tema seguindo o sistema
import sys

from PySide6.QtCore import QSettings, Qt, QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QApplication, QHBoxLayout, QListWidget, QMainWindow, QStackedWidget, QWidget

from . import hotkeys, theme
from .devices import list_cameras, list_mics, pick_default
from .home import HomePage
from .pages import DevicesPage, SettingsPage, ShortcutsPage, SupportPage
from .setup import ITEMS, Checks, SetupPage
from .tour import Tour
from .worker import EngineWorker


class MainWindow(QMainWindow):
    def __init__(self, cameras=None, mics=None):
        super().__init__()
        self.setWindowTitle("Ilusio")
        self.resize(1040, 700)
        self.setMinimumSize(900, 620)
        self.settings = s = QSettings(QSettings.defaultFormat(), QSettings.Scope.UserScope, "Ilusio", "Ilusio")
        self.cameras = list_cameras() if cameras is None else cameras
        default = pick_default(self.cameras, s.value("camera"))
        self.combos = {a: hotkeys.Combo.parse(s.value(f"hotkey/{a}")) if s.value(f"hotkey/{a}") else c
                       for a, c in hotkeys.DEFAULTS.items()}

        # páginas
        self.home = HomePage(self.cameras)
        if default:
            self.home.camera.setCurrentIndex(self.cameras.index(default))
        self.devices = DevicesPage(list_mics() if mics is None else mics, s.value("mic", ""), int(s.value("fps", 30)),
                                   float(s.value("gain", 0.8)), float(s.value("reach", 1.5)))
        self.setup = SetupPage()
        self.shortcuts = ShortcutsPage(self.combos)
        self.support = SupportPage()
        self.settings_page = SettingsPage(s.value("theme", "system"))
        self.nav = QListWidget()
        self.nav.setObjectName("nav")
        self.nav.setFixedWidth(190)
        self.pages = QStackedWidget()
        self.labels = [("▶", "Início", self.home), ("🎙", "Câmera e mic", self.devices), ("☑", "Configuração", self.setup),
                       ("⌨", "Atalhos", self.shortcuts), ("♡", "Apoiar", self.support), ("⚙", "Ajustes", self.settings_page)]
        for icon, label, page in self.labels:
            self.nav.addItem(f"{icon}   {label}")
            self.pages.addWidget(page)
        self.nav.currentRowChanged.connect(self.pages.setCurrentIndex)
        self.nav.setCurrentRow(0)

        main = QWidget()
        row = QHBoxLayout(main)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(0)
        row.addWidget(self.nav)
        row.addWidget(self.pages, 1)
        self.tour = Tour()
        self.tour.finished.connect(self._tour_finished)
        self.root = QStackedWidget()
        self.root.addWidget(main)
        self.root.addWidget(self.tour)
        self.setCentralWidget(self.root)
        if not s.value("onboarded", False, type=bool):  # tour só na primeira abertura
            self.root.setCurrentWidget(self.tour)

        # motor
        self.worker = EngineWorker()
        self.worker.frame.connect(self.home.preview.set_frame)
        self.worker.state.connect(self._on_state)
        self.worker.failed.connect(self.home.error.setText)
        self.worker.stopped.connect(self._on_stopped)
        self._restart = False  # câmera, microfone ou fps trocados ligado: religa quando o motor terminar de parar
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
        self.settings_page.replay_tour.connect(lambda: self.root.setCurrentWidget(self.tour))

        # checklist: confere a cada 2 s (privacidade liberada, VB-Cable instalado...)
        self.setup.go_home.connect(lambda: self.nav.setCurrentRow(0))
        self.setup.call_app_done.connect(lambda: self._mark("call_app"))
        self.check_timer = QTimer(self)
        self.check_timer.timeout.connect(self.refresh_checks)
        self.check_timer.start(2000)
        self.refresh_checks()

        # atalhos globais
        self.hotkeys = hotkeys.HotkeyManager(self._hotkey)
        QApplication.instance().installNativeEventFilter(self.hotkeys)
        self._register_hotkeys()
        self.shortcuts.changed.connect(self._shortcut_changed)
        self.shortcuts.reset.connect(self._reset_shortcuts)
        self.shortcuts.recording.connect(lambda on: self.hotkeys.suspend() if on else self._register_hotkeys())

        hints = QGuiApplication.styleHints()
        hints.colorSchemeChanged.connect(self._apply_theme)
        self._apply_theme(hints.colorScheme())

    # tema
    def _apply_theme(self, scheme=None):
        chosen = self.settings.value("theme", "system")
        if chosen == "system":
            scheme = QGuiApplication.styleHints().colorScheme() if scheme is None else scheme
            chosen = "dark" if scheme == Qt.ColorScheme.Dark else "light"
        self.setStyleSheet(theme.stylesheet(chosen))

    def _theme_chosen(self, value):
        self.settings.setValue("theme", value)
        self._apply_theme()

    # tour e checklist
    def _tour_finished(self, open_setup):
        self.settings.setValue("onboarded", True)
        self.root.setCurrentIndex(0)
        if open_setup:
            self.nav.setCurrentRow(self.pages.indexOf(self.setup))

    def _mark(self, item):
        self.settings.setValue(f"setup/{item}", True)
        self.refresh_checks()

    def refresh_checks(self):
        flag = lambda item: self.settings.value(f"setup/{item}", False, type=bool)
        checks = Checks.current(flag("background"), flag("gesture"), flag("call_app"))
        self.setup.refresh(checks)
        row = self.pages.indexOf(self.setup)
        badge = "" if checks.done == len(ITEMS) else f"  {checks.done}/{len(ITEMS)}"
        self.nav.item(row).setText(f"☑   Configuração{badge}")

    # atalhos
    def _register_hotkeys(self):
        for action, combo in self.combos.items():
            ok = self.hotkeys.register(action, combo)
            if not ok and sys.platform == "win32":
                self.shortcuts.show_result(action, combo, "Não registrado: outro app usa essa combinação.")

    def _shortcut_changed(self, action, combo):
        other = hotkeys.conflict(action, combo, self.combos)
        if other:
            self.shortcuts.show_result(action, combo, f"Já usado em “{hotkeys.ACTIONS[other]}”.")
            return
        previous = self.combos[action]
        self.combos[action] = combo
        if sys.platform == "win32" and not self.hotkeys.register(action, combo):
            self.combos[action] = previous
            self.shortcuts.show_result(action, previous, f"Outro app já usa {combo}.")
            return
        self.settings.setValue(f"hotkey/{action}", combo.dump())
        self.shortcuts.show_result(action, combo, None)

    def _reset_shortcuts(self):
        for action, combo in hotkeys.DEFAULTS.items():
            self.settings.remove(f"hotkey/{action}")
            self.combos[action] = combo
            self.shortcuts.show_result(action, combo, None)
        self._register_hotkeys()

    def _hotkey(self, action):
        if action == "power":
            self._toggle_power()
        elif action == "background":
            self.worker.send("capture_bg")
        else:
            self.worker.send(action)  # toggle, reappear

    # motor
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
        if not self.cameras:
            return
        self.home.error.setText("")
        camera = self.cameras[self.home.camera.currentIndex()]
        s = self.settings
        self.worker.start(camera.index, fps=int(s.value("fps", 30)), gain=float(s.value("gain", 0.8)),
                          reach=float(s.value("reach", 1.5)), mic=s.value("mic", "") or None)
        self.home.set_running(True)

    def _on_stopped(self):
        self.home.set_running(False)
        self.devices.set_running(False)
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
        for item, done in (("background", state["bg_ready"]), ("gesture", state["gesture_seen"])):
            if done and not self.settings.value(f"setup/{item}", False, type=bool):
                self._mark(item)

    def closeEvent(self, event):
        self.worker.stop()
        self.hotkeys.suspend()
        super().closeEvent(event)
