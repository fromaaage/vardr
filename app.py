#!/usr/bin/env python3
"""Garuda Pilot - one-click system maintenance for Garuda/Arch."""
import os
import sys

from PySide6.QtCore import QObject, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from runner import Runner
from settings import Settings

HERE = os.path.dirname(os.path.abspath(__file__))


class Actions(QObject):
    """Maintenance actions exposed to QML."""

    def __init__(self, runner, settings, parent=None):
        super().__init__(parent)
        self.runner = runner
        self.settings = settings

    @Slot()
    def update(self):
        cmd = self.settings.get("update_command").strip()
        if cmd:
            self.runner.start(cmd, as_root=bool(self.settings.get("update_as_root")))


def main():
    QQuickStyle.setStyle("Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Garuda Pilot")
    app.setDesktopFileName("garuda-pilot")

    settings = Settings()
    runner = Runner()
    actions = Actions(runner, settings)

    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("settings", settings)
    ctx.setContextProperty("runner", runner)
    ctx.setContextProperty("actions", actions)
    engine.load(os.path.join(HERE, "Main.qml"))
    if not engine.rootObjects():
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
