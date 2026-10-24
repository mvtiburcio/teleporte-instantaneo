# theme.py — visual no estilo Fluent do Windows 11 com o laranja do Ilusio; claro/escuro seguem o sistema
ACCENT = "#FF8A1F"
GREEN = "#2ECC71"

PALETTES = {
    "dark": {"bg": "#202024", "nav": "#1B1B1F", "card": "#2B2B30", "border": "#3A3A40", "text": "#FFFFFF",
             "muted": "#A8A8B0", "hover": "#2F2F35", "sel": "#34343B", "btn": "#33333A"},
    "light": {"bg": "#F3F3F3", "nav": "#EBEBEB", "card": "#FFFFFF", "border": "#E0E0E0", "text": "#1B1B1B",
              "muted": "#5F5F66", "hover": "#E4E4E4", "sel": "#DDDDDD", "btn": "#FFFFFF"},
}


def stylesheet(scheme):
    p = PALETTES["dark" if scheme == "dark" else "light"]
    return f"""
    QWidget {{ background: {p['bg']}; color: {p['text']}; font-family: "Segoe UI Variable", "Segoe UI", sans-serif; font-size: 10pt; }}
    #nav {{ background: {p['nav']}; border: none; padding: 6px; outline: 0; }}
    #nav::item {{ padding: 9px 12px; border-radius: 5px; margin: 1px 0; }}
    #nav::item:hover {{ background: {p['hover']}; }}
    #nav::item:selected {{ background: {p['sel']}; color: {p['text']}; border-left: 3px solid {ACCENT}; }}
    QPushButton {{ background: {p['btn']}; border: 1px solid {p['border']}; border-radius: 5px; padding: 8px 16px; font-weight: 600; }}
    QPushButton:hover {{ background: {p['hover']}; }}
    QPushButton:disabled {{ color: {p['muted']}; }}
    QPushButton#primary {{ background: {ACCENT}; color: #1B1B1B; border: none; }}
    QPushButton#primary:hover {{ background: #FF9D42; }}
    QPushButton#primary:disabled {{ background: {p['sel']}; color: {p['muted']}; }}
    QComboBox {{ background: {p['btn']}; border: 1px solid {p['border']}; border-radius: 5px; padding: 6px 10px; }}
    #preview {{ background: #2A2D3D; border-radius: 8px; border: 2px solid transparent; }}
    #preview[gesture="true"] {{ border: 2px solid {GREEN}; }}
    #chip {{ background: rgba(20, 20, 26, 150); color: #FFFFFF; border-radius: 11px; padding: 4px 10px; font-weight: 600; }}
    #guide {{ background: rgba(20, 20, 26, 190); color: #FFFFFF; border-radius: 16px; padding: 18px 28px; }}
    #muted {{ color: {p['muted']}; background: transparent; }}
    #error {{ color: #E5484D; background: transparent; }}
    """
