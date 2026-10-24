import os, sys, tempfile, unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

from PySide6.QtCore import QSettings
QSettings.setDefaultFormat(QSettings.Format.IniFormat)
QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, tempfile.mkdtemp(prefix="ilusio-testes-"))

from ilusio_win import hotkeys
from ilusio_win.setup import Checks, ITEMS


class HotkeysTest(unittest.TestCase):
    def test_padroes_sao_ctrl_alt_shift_e_distintos(self):
        combos = [hotkeys.DEFAULTS[a] for a in hotkeys.ACTIONS]
        self.assertTrue(all(c.mods == hotkeys.CTRL | hotkeys.ALT | hotkeys.SHIFT for c in combos))
        self.assertEqual(len(set(combos)), len(combos))

    def test_texto_do_atalho(self):
        self.assertEqual(str(hotkeys.DEFAULTS["toggle"]), "Ctrl+Alt+Shift+T")

    def test_exige_ctrl_ou_alt(self):
        self.assertTrue(hotkeys.allowed(hotkeys.CTRL | hotkeys.SHIFT))
        self.assertFalse(hotkeys.allowed(hotkeys.SHIFT))
        self.assertFalse(hotkeys.allowed(0))

    def test_conflito_entre_acoes(self):
        combos = dict(hotkeys.DEFAULTS)
        self.assertEqual(hotkeys.conflict("power", combos["toggle"], combos), "toggle")
        self.assertIsNone(hotkeys.conflict("toggle", combos["toggle"], combos))

    def test_so_aceita_letra_digito_espaco_e_f(self):
        from PySide6.QtCore import QEvent, Qt
        from PySide6.QtGui import QKeyEvent
        mods = Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.AltModifier
        key = lambda k: hotkeys.from_key_event(QKeyEvent(QEvent.Type.KeyPress, k, mods))
        self.assertEqual(key(Qt.Key.Key_K), hotkeys.Combo(hotkeys.CTRL | hotkeys.ALT, ord("K")))
        self.assertEqual(str(key(Qt.Key.Key_F5)), "Ctrl+Alt+F5")
        self.assertIsNone(key(Qt.Key.Key_Left))

    def test_perder_o_foco_encerra_a_gravacao(self):
        from PySide6.QtCore import Qt
        from PySide6.QtGui import QFocusEvent
        from PySide6.QtWidgets import QApplication
        from ilusio_win.pages import KeyButton
        app = QApplication.instance() or QApplication([])
        b = KeyButton(hotkeys.DEFAULTS["toggle"])
        estados = []
        b.recording.connect(estados.append)
        b.start()
        b.focusOutEvent(QFocusEvent(QFocusEvent.Type.FocusOut, Qt.FocusReason.MouseFocusReason))
        self.assertFalse(b.active)
        self.assertEqual(estados, [True, False])
        self.assertEqual(b.text(), "Ctrl+Alt+Shift+T")

    def test_texto_salvo_volta_igual(self):
        c = hotkeys.Combo(hotkeys.CTRL | hotkeys.ALT, ord("K"))
        self.assertEqual(hotkeys.Combo.parse(c.dump()), c)


class ChecksTest(unittest.TestCase):
    def test_contagem_e_primeiro_pendente(self):
        self.assertEqual(Checks().done, 0)
        c = Checks(camera=True, mic=True)
        self.assertEqual(c.first_pending, "virtual_camera")
        everything = Checks(**{k: True for k in ITEMS})
        self.assertEqual(everything.done, len(ITEMS))
        self.assertIsNone(everything.first_pending)


class WindowTabsTest(unittest.TestCase):
    def test_abas_e_tour_na_primeira_abertura(self):
        from PySide6.QtWidgets import QApplication
        from ilusio_win.app import MainWindow
        app = QApplication.instance() or QApplication([])
        w = MainWindow(cameras=[], mics=[])
        names = [w.nav.item(i).text().split(maxsplit=1)[1].split("  ")[0] for i in range(w.nav.count())]
        self.assertEqual(names, ["Início", "Câmera e mic", "Configuração", "Atalhos", "Apoiar", "Ajustes"])
        self.assertTrue(w.tour.isVisible() or not w.settings.value("onboarded", False, type=bool))
        w.tour.finish(open_setup=True)
        self.assertTrue(w.settings.value("onboarded", False, type=bool))
        self.assertIs(w.pages.currentWidget(), w.setup)
        w.close()


if __name__ == "__main__":
    unittest.main()
