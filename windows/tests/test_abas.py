import os, sys, tempfile, unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

from PySide6.QtCore import QSettings
QSettings.setDefaultFormat(QSettings.Format.IniFormat)
QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, tempfile.mkdtemp(prefix="ilusio-testes-"))

from ilusio_win import pix


class PixTest(unittest.TestCase):
    def test_crc16_padrao(self):
        self.assertEqual(pix.crc16("123456789"), "29B1")

    def test_exemplo_do_bcb(self):
        self.assertEqual(pix.payload("123e4567-e12b-12d1-a456-426655440000", "Fulano de Tal", "BRASILIA"),
                         "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000"
                         "5204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D")

    def test_mesmo_pix_do_app_de_mac(self):
        self.assertEqual(pix.ILUSIO, "00020126580014br.gov.bcb.pix0136d1fef5be-4e51-4a50-86fb-8810cb8bfcd4"
                                     "5204000053039865802BR5906ILUSIO6006RECIFE62070503***63048C40")

    def test_qr_le_de_volta_igual(self):
        import cv2
        img = pix.qr_bgr(pix.ILUSIO)
        data, _, _ = cv2.QRCodeDetector().detectAndDecode(img)
        self.assertEqual(data, pix.ILUSIO)


class AbasTest(unittest.TestCase):
    def test_janela_tem_as_abas_e_o_tema_escolhido_vale(self):
        from PySide6.QtWidgets import QApplication
        from ilusio_win.app import MainWindow
        app = QApplication.instance() or QApplication([])
        w = MainWindow(cameras=[], mics=["Microfone USB"])
        nomes = [w.nav.item(i).text().split(maxsplit=1)[1] for i in range(w.nav.count())]
        self.assertEqual(nomes, ["Início", "Câmera e mic", "Apoiar", "Ajustes"])
        w.settings_page.theme.setCurrentIndex(2)  # Escuro
        self.assertEqual(w.settings.value("theme"), "dark")
        self.assertIn("#202024", w.styleSheet())  # fundo do tema escuro
        w.close()


if __name__ == "__main__":
    unittest.main()
