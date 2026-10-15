"""Иконка: волна, на ней кубик и шар.

Рисуем в край — macOS обрежет по своей маске. Сетка с шагом 16.
"""
import sys
from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (QBrush, QColor, QGuiApplication, QImage, QLinearGradient,
                           QPainter, QPainterPath, QPen)

S, U = 1024, 16
TOP, LOW = QColor("#3a8ee6"), QColor("#1d4f9c")
WATER, FOAM, BODY = QColor("#7cc4ff"), QColor("#e8f4ff"), QColor("#f6f8fb")


def wave(y, amp, phase=0.0):
    path = QPainterPath()
    path.moveTo(0, y)
    import math
    for x in range(0, S + 1, 8):
        path.lineTo(x, y + amp * math.sin(x / S * math.pi * 2.2 + phase))
    return path


def draw(path, layer=False):
    QGuiApplication.instance() or QGuiApplication([])
    img = QImage(S, S, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    if not layer:
        back = QLinearGradient(0, 0, 0, S)
        back.setColorAt(0.0, TOP)
        back.setColorAt(1.0, LOW)
        p.fillRect(QRectF(0, 0, S, S), QBrush(back))

    # Кубик, чуть повёрнутый, и шар — наполовину в воде.
    p.save()
    p.translate(22 * U, 30 * U)
    p.rotate(-12)
    p.setPen(Qt.NoPen)
    p.setBrush(BODY)
    p.drawRoundedRect(QRectF(-6.5 * U, -6.5 * U, 13 * U, 13 * U), 2 * U, 2 * U)
    p.restore()
    p.setBrush(BODY)
    p.drawEllipse(QPointF(42 * U, 32 * U), 5.5 * U, 5.5 * U)

    # Вода поверх нижней половины тел.
    surface = wave(34 * U, 1.4 * U)
    body = QPainterPath(surface)
    body.lineTo(S, S)
    body.lineTo(0, S)
    body.closeSubpath()
    water = QColor(WATER)
    water.setAlpha(235)
    p.fillPath(body, water)
    p.setPen(QPen(FOAM, 1.5 * U, Qt.SolidLine, Qt.RoundCap))
    p.setBrush(Qt.NoBrush)
    p.drawPath(surface)
    # Брызги над водой.
    p.setPen(Qt.NoPen)
    p.setBrush(FOAM)
    for x, y, r in ((14, 20, 1.0), (31, 18, 0.8), (36, 22, 0.6), (48, 21, 0.9)):
        p.drawEllipse(QPointF(x * U, y * U), r * U, r * U)
    p.end()
    img.save(path)


if __name__ == "__main__":
    draw(sys.argv[1] if len(sys.argv) > 1 else "icon/AppIcon-1024.png",
         len(sys.argv) > 2 and sys.argv[2] == "layer")
