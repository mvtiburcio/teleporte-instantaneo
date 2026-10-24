# python -m ilusio_win (a partir de windows/) — abre o Ilusio
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT not in sys.path:  # em desenvolvimento o motor (teleporte.py) fica na raiz do repositório
    sys.path.insert(0, ROOT)

from PySide6.QtWidgets import QApplication

from ilusio_win.app import MainWindow


def check():
    """Ilusio.exe --check (CI): o executável congelado acha o som e carrega os modelos do MediaPipe."""
    import teleporte as tp
    tp.Teleporter(on_fire=lambda: None)
    return 0 if os.path.exists(tp.SOUND) else 1


def main():
    if "--check" in sys.argv:
        return check()
    app = QApplication(sys.argv)
    app.setApplicationName("Ilusio")
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
