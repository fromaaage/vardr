#!/usr/bin/env python3
"""Generate the Varðr icon and wordmark as SVG from Inter Display Black (OFL).

The ð crossbar is overlaid in the accent color. Needs the Inter font installed.
Usage: python packaging/make-logo.py   (writes icons/vardr.svg, docs/wordmark-*.svg)
"""
import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtGui import QFont, QFontMetricsF, QGuiApplication, QPainterPath  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACCENT = "#ff2bd6"
BG_TOP, BG_BOTTOM = "#1c1c1f", "#0b0b0d"
REF_SIZE = 700  # pixel size the crossbar polygon was measured at
# Crossbar of "ð" in Inter Display Black, glyph coordinates at REF_SIZE
CROSSBAR = [(64.2, -400.2), (317.2, -532.2), (317.2, -477.2), (64.2, -343.2)]


def font(size):
    f = QFont("Inter Display")
    f.setPixelSize(size)
    f.setWeight(QFont.Black)
    return f


def svg_path(path):
    """QPainterPath -> SVG path data."""
    out, i, els = [], 0, [path.elementAt(k) for k in range(path.elementCount())]
    while i < len(els):
        e = els[i]
        if e.type == QPainterPath.MoveToElement:
            out.append(f"M{e.x:.1f} {e.y:.1f}")
        elif e.type == QPainterPath.LineToElement:
            out.append(f"L{e.x:.1f} {e.y:.1f}")
        elif e.type == QPainterPath.CurveToElement:
            c2, end = els[i + 1], els[i + 2]
            out.append(f"C{e.x:.1f} {e.y:.1f} {c2.x:.1f} {c2.y:.1f} {end.x:.1f} {end.y:.1f}")
            i += 2
        i += 1
    return "".join(out) + "Z"


def crossbar(scale, dx, dy):
    pts = " ".join(f"{x * scale + dx:.1f},{y * scale + dy:.1f}" for x, y in CROSSBAR)
    return f'<polygon points="{pts}" fill="{ACCENT}"/>'


def icon():
    size = 760
    path = QPainterPath()
    path.addText(0, 0, font(size), "ð")
    r = path.boundingRect()
    dx, dy = 512 - r.center().x(), 530 - r.center().y()  # optically a bit low
    s = size / REF_SIZE
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{BG_TOP}"/>
      <stop offset="1" stop-color="{BG_BOTTOM}"/>
    </linearGradient>
  </defs>
  <rect x="32" y="32" width="960" height="960" rx="216" fill="url(#bg)" stroke="#2c2c30" stroke-width="6"/>
  <g transform="translate({dx:.1f} {dy:.1f})">
    <path fill="#ffffff" d="{svg_path(path)}"/>
    {crossbar(s, 0, 0)}
  </g>
</svg>
'''


def wordmark(color):
    size = 200
    f = font(size)
    path = QPainterPath()
    path.addText(0, 0, f, "varðr")
    r = path.boundingRect()
    eth_x = QFontMetricsF(f).horizontalAdvance("var")
    pad = 20
    w, h = r.width() + 2 * pad, r.height() + 2 * pad
    dx, dy = pad - r.left(), pad - r.top()
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" viewBox="0 0 {w:.0f} {h:.0f}">
  <g transform="translate({dx:.1f} {dy:.1f})">
    <path fill="{color}" d="{svg_path(path)}"/>
    {crossbar(size / REF_SIZE, eth_x, 0)}
  </g>
</svg>
'''


def main():
    QGuiApplication([])
    os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
    files = {
        "icons/vardr.svg": icon(),
        "docs/wordmark-dark.svg": wordmark("#ffffff"),   # for dark backgrounds
        "docs/wordmark-light.svg": wordmark("#111111"),  # for light backgrounds
    }
    for name, content in files.items():
        with open(os.path.join(ROOT, name), "w") as fh:
            fh.write(content)
        print("wrote", name)


if __name__ == "__main__":
    main()
