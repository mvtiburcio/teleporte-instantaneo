# hotkeys.py — atalhos globais do Windows (RegisterHotKey): funcionam com a chamada em primeiro plano
import sys
from dataclasses import dataclass

from PySide6.QtCore import QAbstractNativeEventFilter, Qt

ALT, CTRL, SHIFT, WIN = 0x1, 0x2, 0x4, 0x8  # MOD_* da API do Windows
MOD_NOREPEAT, WM_HOTKEY = 0x4000, 0x0312

ACTIONS = {
    "toggle": "Sumir / voltar",
    "power": "Ligar / desligar o Ilusio",
    "background": "Gravar o fundo",
    "reappear": "Reaparecer na hora (sem efeito)",
}


@dataclass(frozen=True)
class Combo:
    mods: int
    vk: int  # código virtual da tecla (letras e dígitos = ASCII maiúsculo)

    def __str__(self):
        names = [n for bit, n in ((CTRL, "Ctrl"), (ALT, "Alt"), (SHIFT, "Shift"), (WIN, "Win")) if self.mods & bit]
        key = f"F{self.vk - 0x6F}" if 0x70 <= self.vk <= 0x7B else ("Espaço" if self.vk == 0x20 else chr(self.vk))
        return "+".join(names + [key])

    def dump(self):
        return f"{self.mods}:{self.vk}"

    @staticmethod
    def parse(text):
        mods, vk = text.split(":")
        return Combo(int(mods), int(vk))


# Ctrl+Alt sozinho é o AltGr do teclado ABNT2 (roubaria caracteres) e Ctrl+Shift+T é "reabrir aba": Ctrl+Alt+Shift
DEFAULTS = {action: Combo(CTRL | ALT | SHIFT, ord(key)) for action, key in zip(ACTIONS, "TLBR")}


def allowed(mods):
    return bool(mods & (CTRL | ALT))


def conflict(action, combo, combos):
    """Outra ação que já usa a combinação (a própria não conta)."""
    return next((a for a, c in combos.items() if a != action and c == combo), None)


def from_key_event(event):
    """Combinação de uma tecla pressionada no gravador; None se não tiver Ctrl/Alt ou se for só modificador."""
    qt_mods = event.modifiers()
    mods = sum(bit for flag, bit in ((Qt.KeyboardModifier.ControlModifier, CTRL), (Qt.KeyboardModifier.AltModifier, ALT),
                                     (Qt.KeyboardModifier.ShiftModifier, SHIFT), (Qt.KeyboardModifier.MetaModifier, WIN))
               if qt_mods & flag)
    key = event.key()
    if key in (Qt.Key.Key_Control, Qt.Key.Key_Alt, Qt.Key.Key_Shift, Qt.Key.Key_Meta) or not allowed(mods):
        return None
    if sys.platform == "win32" and event.nativeVirtualKey():
        return Combo(mods, event.nativeVirtualKey())
    if Qt.Key.Key_F1 <= key <= Qt.Key.Key_F12:
        return Combo(mods, 0x70 + key - Qt.Key.Key_F1)
    return Combo(mods, key) if 0x20 <= key <= 0x5A else None


class HotkeyManager(QAbstractNativeEventFilter):
    """Registra os atalhos e chama on_action(ação) quando o Windows avisa (WM_HOTKEY). Fora do Windows, não faz nada."""

    def __init__(self, on_action):
        super().__init__()
        self.on_action = on_action
        self.ids = {}  # id do Windows → ação

    def register(self, action, combo):
        if sys.platform != "win32":
            return False
        import ctypes
        hid = list(ACTIONS).index(action) + 1
        ctypes.windll.user32.UnregisterHotKey(None, hid)
        ok = bool(ctypes.windll.user32.RegisterHotKey(None, hid, combo.mods | MOD_NOREPEAT, combo.vk))
        if ok:
            self.ids[hid] = action
        return ok

    def suspend(self):  # durante a gravação de um atalho: a tecla tem que chegar no gravador
        if sys.platform == "win32":
            import ctypes
            for hid in list(self.ids):
                ctypes.windll.user32.UnregisterHotKey(None, hid)
            self.ids.clear()

    def nativeEventFilter(self, event_type, message):
        if event_type == b"windows_generic_MSG":
            import ctypes.wintypes
            msg = ctypes.wintypes.MSG.from_address(int(message))
            if msg.message == WM_HOTKEY and msg.wParam in self.ids:
                self.on_action(self.ids[msg.wParam])
                return True, 0
        return False, 0
