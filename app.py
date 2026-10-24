#!/usr/bin/env python3
"""varðr - system update guardian for Arch-based systems."""
import glob
import os
import shlex
import shutil
import subprocess
import sys

from PySide6.QtCore import QMetaObject, QObject, QRectF, Property, Signal, Slot
from PySide6.QtGui import QColor, QIcon, QPainter, QPixmap
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from checker import UpdateChecker
from repos import RepoEditor, mirrors_script
from runner import Runner
from settings import Settings

__version__ = "1.0.0"

HERE = os.path.dirname(os.path.abspath(__file__))
APP_ID = "vardr"
OLD_ID = "garuda-pilot"  # name before 1.0.0, migrated on start
AUTOSTART = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
                         "autostart", f"{APP_ID}.desktop")
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
        self._plan = []
        self._repo_script = ""
        runner.finished.connect(self._next)

    def _get_step(self):
        if not self._step:
            return ""
        prefix = f"Step {self._index}/{self._total} · " if self._total > 1 else ""
        return prefix + self._step

    def _get_index(self):
        return self._index if self._step else 0

    def _get_plan(self):
        return self._plan

    def _get_total(self):
        return self._total if self._step else 0

    step = Property(str, _get_step, notify=stepChanged)
    stepIndex = Property(int, _get_index, notify=stepChanged)
    plan = Property("QVariantList", _get_plan, notify=stepChanged)
    stepTotal = Property(int, _get_total, notify=stepChanged)

    @Slot(result=str)
    def detectedAurHelper(self):
        return aur_helper(self.settings.get("aur_helper"))

    # --- steps: (label, callable that starts the runner or returns False) ---
    def _update(self):
        cmd = self.settings.get("update_command").strip()
        if not cmd:
            self.runner.note("No update command set, skipped.")
            return False
        return self.runner.start(cmd, as_root=bool(self.settings.get("update_as_root")))

    def _aur(self):
        helper = self.detectedAurHelper()
        if not helper:
            self.runner.note("No AUR helper (paru/yay) found, skipped.")
            return False
        if not has_foreign_packages():
            self.runner.note("No AUR packages installed, skipped.")
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
            self.runner.note("No AUR build cache found, skipped.")
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
            self.runner.note("No fix command set, skipped.")
            return False
        return self.runner.start(cmd, as_root=bool(self.settings.get("fix_as_root")))

    def _repos_save(self):
        return self.runner.start(self._repo_script, as_root=True, display="Save pacman.conf")

    def _mirrors(self):
        if not shutil.which("rate-mirrors"):
            self.runner.note("rate-mirrors is not installed, skipped.")
            return False
        return self.runner.start(mirrors_script(), as_root=True, display="Rank mirrors (rate-mirrors)")

    STEPS = {
        "update": ("System update", "_update"),
        "aur": ("AUR update", "_aur"),
        "cache_pacman": ("Clean pacman cache", "_cache_pacman"),
        "cache_aur": ("Clean AUR cache", "_cache_aur"),
        "fix": ("Garuda fix", "_fix"),
        "repos_save": ("Save repositories", "_repos_save"),
        "mirrors": ("Rank mirrors", "_mirrors"),
    }

    def _run(self, keys):
        if self.runner.running:
            return
        self._queue = list(keys)
        self._plan = [self.STEPS[k][0] for k in keys]
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

    @Slot(str)
    def saveRepos(self, script):
        """Install the new pacman.conf, then run a full update (no partial -Sy)."""
        self._repo_script = script
        self._run(["repos_save", "update"])

    @Slot()
    def mirrors(self):
        self._run(["mirrors"])

    @Slot()
    def fix(self):
        self._run(["fix"])

    @Slot()
    def cleanCache(self):
        self._run(["cache_pacman", "cache_aur"])

    @Slot()
    def updateAll(self):
        self._run(["update", "aur", "cache_pacman", "cache_aur"])


APP_ICON = os.path.join(HERE, "icons", "vardr.svg")


def tray_icon(badge):
    """App icon, with a red dot in the corner when updates are waiting."""
    pix = QPixmap(64, 64)
    pix.fill(QColor(0, 0, 0, 0))
    p = QPainter(pix)
    p.setRenderHint(QPainter.Antialiasing)
    QSvgRenderer(APP_ICON).render(p, QRectF(0, 0, 64, 64))
    if badge:
        p.setPen(QColor("white"))
        p.setBrush(QColor("#ff453a"))
        p.drawEllipse(QRectF(38, 0, 26, 26))
    p.end()
    return QIcon(pix)


def migrate_old_name():
    """Carry settings over from garuda-pilot and drop its autostart entry."""
    config = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    old, new = os.path.join(config, OLD_ID), os.path.join(config, APP_ID)
    if os.path.isdir(old) and not os.path.exists(new):
        shutil.copytree(old, new)
    old_autostart = os.path.join(config, "autostart", f"{OLD_ID}.desktop")
    if os.path.exists(old_autostart):
        os.remove(old_autostart)


def launch_command():
    """Installed: plain command; from source: python + this file."""
    return APP_ID if shutil.which(APP_ID) else f"{sys.executable} {os.path.join(HERE, 'app.py')}"


def sync_autostart(enabled):
    if enabled:
        os.makedirs(os.path.dirname(AUTOSTART), exist_ok=True)
        with open(AUTOSTART, "w") as f:
            f.write("[Desktop Entry]\nType=Application\nName=varðr\n"
                    f"Exec={launch_command()} --tray\nIcon={APP_ICON}\n"
                    "X-GNOME-Autostart-enabled=true\n")
    elif os.path.exists(AUTOSTART):
        os.remove(AUTOSTART)


def other_instance(start_hidden):
    """If varðr already runs, ask it to show its window and return True."""
    sock = QLocalSocket()
    sock.connectToServer(f"{APP_ID}-{os.getuid()}")
    if not sock.waitForConnected(300):
        return False
    if not start_hidden:
        sock.write(b"show")
        sock.waitForBytesWritten(300)
    sock.disconnectFromServer()
    return True


def main():
    start_hidden = "--tray" in sys.argv
    QQuickStyle.setStyle("Basic")
    app = QApplication(sys.argv)
    app.setApplicationName("varðr")
    app.setApplicationVersion(__version__)
    app.setDesktopFileName(APP_ID)
    app.setWindowIcon(QIcon(APP_ICON))
    if other_instance(start_hidden):
        return

    server_name = f"{APP_ID}-{os.getuid()}"
    QLocalServer.removeServer(server_name)
    server = QLocalServer()
    server.listen(server_name)

    migrate_old_name()
    settings = Settings()
    runner = Runner()
    actions = Actions(runner, settings)
    checker = UpdateChecker(settings, actions.detectedAurHelper)
    actions.done.connect(lambda code: checker.check())  # refresh count after any run
    sync_autostart(settings.get("autostart"))
    settings.changed.connect(lambda: sync_autostart(settings.get("autostart")))

    tray_ok = QSystemTrayIcon.isSystemTrayAvailable()
    app.setQuitOnLastWindowClosed(not tray_ok)

    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("settings", settings)
    ctx.setContextProperty("runner", runner)
    ctx.setContextProperty("actions", actions)
    ctx.setContextProperty("checker", checker)
    ctx.setContextProperty("trayAvailable", tray_ok)
    ctx.setContextProperty("startHidden", start_hidden and tray_ok)
    repo_editor = RepoEditor()
    ctx.setContextProperty("repoEditor", repo_editor)
    engine.load(os.path.join(HERE, "Main.qml"))
    if not engine.rootObjects():
        sys.exit(1)
    win = engine.rootObjects()[0]

    def show_window():
        win.show()
        win.raise_()
        win.requestActivate()

    server.newConnection.connect(lambda: (server.nextPendingConnection().readyRead.connect(show_window)))

    if tray_ok:
        tray = QSystemTrayIcon(tray_icon(False), app)
        menu = QMenu()
        menu.addAction("Open", show_window)
        menu.addAction("Check for updates", checker.check)
        menu.addAction("Update all", lambda: (show_window(),
                                              QMetaObject.invokeMethod(win, "startUpdateAll")))
        menu.addSeparator()
        menu.addAction("Quit", app.quit)
        tray.setContextMenu(menu)
        tray.activated.connect(
            lambda reason: show_window() if reason == QSystemTrayIcon.Trigger else None)
        tray.messageClicked.connect(show_window)

        def refresh_tray():
            n = checker.count
            busy = checker.checking or runner.running
            tray.setIcon(tray_icon(n > 0))
            tray.setToolTip("varðr – working…" if busy else
                            f"varðr – {n} update{'s' if n != 1 else ''} available" if n else
                            "varðr – system is up to date")

        checker.changed.connect(refresh_tray)
        checker.checkingChanged.connect(refresh_tray)
        runner.runningChanged.connect(refresh_tray)
        checker.newUpdates.connect(lambda total, aur, names: tray.showMessage(
            f"{total} update{'s' if total != 1 else ''} available"
            + (f" ({aur} AUR)" if aur else ""), names,
            QIcon(APP_ICON), 10_000))
        refresh_tray()
        tray.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
