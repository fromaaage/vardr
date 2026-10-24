"""Background update check: checkupdates (repos) + AUR helper -Qua.

Both run without root and without touching the real sync database."""
import re
import shutil
import time

from PySide6.QtCore import QObject, QProcess, QTimer, Property, Signal, Slot

LINE = re.compile(r"^(\S+)\s+(\S+)\s+->\s+(\S+)")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
INTERVALS = [0, 1, 6, 12, 24]  # hours, 0 = off


def parse_updates(text, source):
    out = []
    for line in ANSI.sub("", text).splitlines():
        m = LINE.match(line.strip())
        if m:
            out.append({"name": m.group(1), "old": m.group(2), "new": m.group(3), "source": source})
    return out


class UpdateChecker(QObject):
    changed = Signal()
    checkingChanged = Signal()
    newUpdates = Signal(int, int, str)  # total, aur, short text for the notification

    def __init__(self, settings, aur_helper, parent=None):
        super().__init__(parent)
        self.settings = settings
        self._aur_helper = aur_helper  # callable -> "paru" | "yay" | ""
        self._packages = []
        self._checking = False
        self._error = ""
        self._repo = []
        self._proc = None
        # Poll once a minute against the stored timestamp, so suspend/restart
        # neither skips nor repeats checks.
        self._timer = QTimer(self)
        self._timer.setInterval(60_000)
        self._timer.timeout.connect(self._tick)
        self._timer.start()
        QTimer.singleShot(5_000, self._tick)

    # --- properties -----------------------------------------------------
    def _get_packages(self):
        return self._packages

    def _get_count(self):
        return len(self._packages)

    def _get_aur_count(self):
        return sum(1 for p in self._packages if p["source"] == "aur")

    def _get_checking(self):
        return self._checking

    def _get_last(self):
        ts = self.settings.get("last_check") or 0
        return time.strftime("%d.%m. %H:%M", time.localtime(ts)) if ts else ""

    def _get_error(self):
        return self._error

    packages = Property("QVariantList", _get_packages, notify=changed)
    count = Property(int, _get_count, notify=changed)
    aurCount = Property(int, _get_aur_count, notify=changed)
    lastCheck = Property(str, _get_last, notify=changed)
    error = Property(str, _get_error, notify=changed)
    checking = Property(bool, _get_checking, notify=checkingChanged)

    @Slot(result="QVariantList")
    def intervals(self):
        return INTERVALS

    # --- checking -------------------------------------------------------
    def _tick(self):
        hours = int(self.settings.get("check_interval") or 0)
        last = self.settings.get("last_check") or 0
        if hours and time.time() - last >= hours * 3600:
            self.check()

    @Slot()
    def check(self):
        if self._checking:
            return
        if not shutil.which("checkupdates"):
            self._finish([], "checkupdates not found (package pacman-contrib)")
            return
        self._checking = True
        self.checkingChanged.emit()
        self._run(["checkupdates", "--nocolor"], self._repo_done)

    def _run(self, argv, callback):
        p = QProcess(self)
        p.finished.connect(lambda code, _status: callback(
            code, bytes(p.readAllStandardOutput()).decode(errors="replace"),
            bytes(p.readAllStandardError()).decode(errors="replace")))
        p.start(argv[0], argv[1:])
        self._proc = p

    def _repo_done(self, code, out, err):
        # checkupdates: 0 = updates, 2 = none, anything else = error
        if code not in (0, 2):
            lines = (err or out).strip().splitlines()
            self._finish([], lines[-1] if lines else f"checkupdates failed ({code})")
            return
        self._repo = parse_updates(out, "repo")
        helper = self._aur_helper() if self.settings.get("check_aur") else ""
        if helper:
            self._run([helper, "-Qua"], self._aur_done)
        else:
            self._finish(self._repo, "")

    def _aur_done(self, code, out, err):
        # paru/yay exit 1 when nothing is outdated; output decides
        self._finish(self._repo + parse_updates(out, "aur"), "")

    def _finish(self, packages, error):
        self._packages = packages
        self._error = error
        self._checking = False
        if not error:
            self.settings.set("last_check", int(time.time()))
            self._notify_if_new()
        self.checkingChanged.emit()
        self.changed.emit()

    def _notify_if_new(self):
        """Notify only for package versions not reported before."""
        current = sorted(f"{p['name']} {p['new']}" for p in self._packages)
        seen = set(self.settings.get("notified") or [])
        fresh = [c for c in current if c not in seen]
        self.settings.set("notified", current)
        if fresh:
            names = ", ".join(c.split()[0] for c in fresh[:5]) + (" …" if len(fresh) > 5 else "")
            self.newUpdates.emit(self._get_count(), self._get_aur_count(), names)
