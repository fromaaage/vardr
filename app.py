#!/usr/bin/env python3
"""Garuda Pilot - one-click system maintenance for Garuda/Arch."""
import glob
import os
import shlex
import shutil
import subprocess
import sys

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from runner import Runner
from settings import Settings

HERE = os.path.dirname(os.path.abspath(__file__))
AUR_HELPERS = ("paru", "yay")
PACMAN_CACHE = "/var/cache/pacman/pkg"
# Build directories of AUR helpers; built packages land in one dir per package
AUR_CACHE_GLOBS = ("~/.cache/paru/clone/*/", "~/.cache/yay/*/")


def aur_helper(choice):
    """Resolve the configured helper ("auto", "paru", "yay") to an installed one."""
    if choice in AUR_HELPERS:
        return choice if shutil.which(choice) else ""
    return next((h for h in AUR_HELPERS if shutil.which(h)), "")


def has_foreign_packages():
    out = subprocess.run(["pacman", "-Qqm"], capture_output=True, text=True).stdout
    return bool(out.strip())


class Actions(QObject):
    """Maintenance actions exposed to QML. Steps run one after another and
    the queue stops at the first failing step."""

    stepChanged = Signal()
    done = Signal(int)

    def __init__(self, runner, settings, parent=None):
        super().__init__(parent)
        self.runner = runner
        self.settings = settings
        self._queue = []
        self._step = ""
        self._index = 0
        self._total = 0
        self._active = False
        runner.finished.connect(self._next)

    def _get_step(self):
        if not self._step:
            return ""
        prefix = f"Step {self._index}/{self._total} · " if self._total > 1 else ""
        return prefix + self._step

    step = Property(str, _get_step, notify=stepChanged)

    @Slot(result=str)
    def detectedAurHelper(self):
        return aur_helper(self.settings.get("aur_helper"))

    # --- steps: (label, callable that starts the runner or returns False) ---
    def _update(self):
        cmd = self.settings.get("update_command").strip()
        if not cmd:
            self.runner.lineAdded.emit("No update command set, skipped.")
            return False
        return self.runner.start(cmd, as_root=bool(self.settings.get("update_as_root")))

    def _aur(self):
        helper = self.detectedAurHelper()
        if not helper:
            self.runner.lineAdded.emit("No AUR helper (paru/yay) found, skipped.")
            return False
        if not has_foreign_packages():
            self.runner.lineAdded.emit("No AUR packages installed, skipped.")
            return False
        # Runs as user; the helper asks for root via pkexec only when installing.
        # cat as pager: PKGBUILD review is printed into the log instead of opening less.
        return self.runner.start(f"{helper} -Sua --sudo pkexec",
                                 env={"PARU_PAGER": "cat", "PAGER": "cat"})

    def _keep(self):
        return max(1, min(3, int(self.settings.get("cache_keep"))))

    def _cache_pacman(self):
        # Keep N versions of installed packages, drop uninstalled ones entirely
        k = self._keep()
        return self.runner.start(
            f"paccache -rk{k}; paccache -ruk0; echo; du -sh {PACMAN_CACHE}", as_root=True)

    def _cache_aur(self):
        dirs = [d for g in AUR_CACHE_GLOBS for d in glob.glob(os.path.expanduser(g))]
        if not dirs:
            self.runner.lineAdded.emit("No AUR build cache found, skipped.")
            return False
        k = self._keep()
        cdirs = " ".join("-c " + shlex.quote(d) for d in dirs)
        roots = " ".join(shlex.quote(os.path.expanduser(r)) for r in ("~/.cache/paru", "~/.cache/yay")
                         if os.path.isdir(os.path.expanduser(r)))
        return self.runner.start(
            f"paccache -rk{k} {cdirs}; paccache -ruk0 {cdirs}; echo; du -sh {roots}",
            display=f"paccache -rk{k}; paccache -ruk0  ({len(dirs)} AUR build dirs)")

    def _fix(self):
        cmd = self.settings.get("fix_command").strip()
        if not cmd:
            self.runner.lineAdded.emit("No fix command set, skipped.")
            return False
        return self.runner.start(cmd, as_root=bool(self.settings.get("fix_as_root")))

    STEPS = {
        "update": ("System update", "_update"),
        "aur": ("AUR update", "_aur"),
        "cache_pacman": ("Clean pacman cache", "_cache_pacman"),
        "cache_aur": ("Clean AUR cache", "_cache_aur"),
        "fix": ("Garuda fix", "_fix"),
    }

    def _run(self, keys):
        if self.runner.running:
            return
        self._queue = list(keys)
        self._total = len(keys)
        self._index = 0
        self._active = True
        self._next(0)

    def _next(self, code):
        if not self._active:
            return
        if code != 0 or not self._queue:
            self._queue = []
            self._step = ""
            self._active = False
            self.stepChanged.emit()
            self.done.emit(code)
            return
        key = self._queue.pop(0)
        label, method = self.STEPS[key]
        self._index += 1
        self._step = label
        self.stepChanged.emit()
        if not getattr(self, method)():
            self._next(0)  # skipped step counts as success

    @Slot()
    def update(self):
        self._run(["update"])

    @Slot()
    def aur(self):
        self._run(["aur"])

    @Slot()
    def fix(self):
        self._run(["fix"])

    @Slot()
    def cleanCache(self):
        self._run(["cache_pacman", "cache_aur"])

    @Slot()
    def updateAll(self):
        self._run(["update", "aur", "cache_pacman", "cache_aur"])


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
