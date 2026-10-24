import os, sys, unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))                    # windows/ (pacote ilusio_win)
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))   # raiz (teleporte.py)

from ilusio_win.devices import Camera, pick_default, real_cameras
from ilusio_win import theme

import tempfile
from PySide6.QtCore import QSettings
# preferências dos testes numa pasta temporária: sem isso, um teste grava a câmera escolhida nas preferências
# reais do usuário e o próximo começa de um estado diferente
QSettings.setDefaultFormat(QSettings.Format.IniFormat)
QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, tempfile.mkdtemp(prefix="ilusio-testes-"))


class DevicesTest(unittest.TestCase):
    cams = [Camera(0, "OBS Virtual Camera"), Camera(1, "USB Webcam"), Camera(2, "Integrated Camera"), Camera(3, "Ilusio Camera")]

    def test_virtuais_nunca_sao_fonte(self):
        self.assertEqual([c.name for c in real_cameras(self.cams)], ["USB Webcam", "Integrated Camera"])

    def test_padrao_e_a_integrada(self):
        self.assertEqual(pick_default(real_cameras(self.cams)).name, "Integrated Camera")

    def test_escolha_salva_vem_primeiro(self):
        self.assertEqual(pick_default(real_cameras(self.cams), saved="USB Webcam").name, "USB Webcam")

    def test_sem_integrada_usa_a_primeira_e_vazio_e_none(self):
        self.assertEqual(pick_default([Camera(5, "Logitech C920")]).name, "Logitech C920")
        self.assertIsNone(pick_default([]))


class ThemeTest(unittest.TestCase):
    def test_claro_e_escuro_usam_o_laranja_e_diferem(self):
        dark, light = theme.stylesheet("dark"), theme.stylesheet("light")
        self.assertIn(theme.ACCENT, dark)
        self.assertIn(theme.ACCENT, light)
        self.assertNotEqual(dark, light)


class WindowTest(unittest.TestCase):
    def test_janela_monta_sem_camera(self):
        from PySide6.QtWidgets import QApplication
        from ilusio_win.app import MainWindow
        app = QApplication.instance() or QApplication([])
        w = MainWindow(cameras=[])
        self.assertEqual(w.windowTitle(), "Ilusio")
        self.assertEqual(w.home.power.text(), "Ligar o Ilusio")
        self.assertFalse(w.home.power.isEnabled())  # sem câmera não liga
        w.close()


class CameraSwitchTest(unittest.TestCase):
    def test_trocar_de_camera_ligado_religa_com_a_nova(self):
        from PySide6.QtWidgets import QApplication
        from ilusio_win.app import MainWindow
        from ilusio_win.devices import Camera
        app = QApplication.instance() or QApplication([])
        w = MainWindow(cameras=[Camera(0, "Integrated Camera"), Camera(1, "USB Webcam")])
        started = []
        w.worker.start = lambda index, fps=30: started.append(index)  # worker falso: sem câmera de verdade
        cls, original = type(w.worker), type(w.worker).running
        cls.running = property(lambda self: True)
        try:
            w.worker.stop = lambda: w._on_stopped()  # parar termina na hora
            w.home.camera.setCurrentIndex(1)
            self.assertEqual(started, [1])
        finally:
            cls.running = original  # devolve a propriedade de verdade pros outros testes
            w.close()


if __name__ == "__main__":
    unittest.main()
