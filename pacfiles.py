"""Find .pacnew/.pacsave files and sort each into "safe to take over" or
"has own changes".

Safe means one of:
  A) current and new file only differ in comments and blank lines
  B) the current file still matches the default of the previous package
     version (from the pacman cache), so the user changed nothing and the
     package only brings new defaults
Everything else is left to the user."""
import datetime
import difflib
import glob
import os
import re
import shlex
import shutil
import subprocess

from PySide6.QtCore import QObject, QProcess, Property, Signal, Slot

SUFFIX = re.compile(r"\.(pacnew|pacsave(\.\d+)?|pacorig)$")
SEARCH_DIRS = ("/etc",)
PKG_EXT = re.compile(r"\.pkg\.tar(\.\w+)?$")


def _run(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def find_files(search_dirs=SEARCH_DIRS, use_pacdiff=True):
    """pacdiff -o (pacman database) plus a find over /etc: the database scan
    misses leftovers of removed packages, find misses unreadable dirs."""
    found = set()
    if use_pacdiff and shutil.which("pacdiff"):
        found.update(l.strip() for l in _run(["pacdiff", "-o", "--nocolor"]).splitlines() if l.strip())
    for top in search_dirs:
        for root, _dirs, files in os.walk(top, onerror=lambda e: None):
            found.update(os.path.join(root, f) for f in files if SUFFIX.search(f))
    return sorted(p for p in found if SUFFIX.search(p) and os.path.lexists(p))


def target_of(path):
    return SUFFIX.sub("", path)


def kind_of(path):
    return SUFFIX.search(path).group(1).split(".")[0]


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return None


def effective(text):
    """Active lines only: no comments, no blank lines, whitespace collapsed."""
    out = []
    for line in text.splitlines():
        s = " ".join(line.split())
        if s and not s.startswith(("#", ";")):
            out.append(s)
    return out


# --- previous package version from the cache ------------------------------
def cache_dirs():
    dirs = [l.strip() for l in _run(["pacman-conf", "CacheDir"]).splitlines() if l.strip()]
    return dirs or ["/var/cache/pacman/pkg/"]


def owner(path):
    out = _run(["pacman", "-Qoq", path]).split()
    return out[0] if out else ""


def old_default(path, dirs=None):
    """File content as shipped by the previously installed package version,
    or None when the package is not in the cache."""
    name = owner(path)
    if not name:
        return None
    installed = _run(["pacman", "-Q", name]).split()
    installed = installed[1] if len(installed) == 2 else ""
    candidates = []
    for d in dirs or cache_dirs():
        for f in glob.glob(os.path.join(d, glob.escape(name) + "-*.pkg.tar*")):
            base = PKG_EXT.sub("", os.path.basename(f))
            if f.endswith(".sig") or base == os.path.basename(f):
                continue
            parts = base.rsplit("-", 3)  # name-pkgver-pkgrel-arch
            if len(parts) == 4 and parts[0] == name and f"{parts[1]}-{parts[2]}" != installed:
                candidates.append(f)
    if not candidates:
        return None
    newest = max(candidates, key=os.path.getmtime)
    try:
        r = subprocess.run(["bsdtar", "-xOf", newest, path.lstrip("/")],
                           capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.decode(errors="replace") if r.returncode == 0 else None


def classify(path, default_lookup=old_default):
    """-> dict for QML: path, target, kind, state (safe|custom|leftover|unreadable), reason."""
    target, kind = target_of(path), kind_of(path)
    item = {"path": path, "target": target, "kind": kind, "state": "", "reason": ""}
    if kind != "pacnew":
        item["state"] = "leftover"
        item["reason"] = ("Saved copy from a removed or changed package. Usually safe to delete."
                          if kind == "pacsave" else "Your file from before the package was installed.")
        return item
    new, cur = read(path), read(target) if os.path.exists(target) else ""
    if new is None or cur is None:
        item["state"], item["reason"] = "unreadable", "Only readable as root – compare it yourself."
        return item
    if not os.path.exists(target):
        item["state"], item["reason"] = "safe", "Current file is missing."
    elif effective(cur) == effective(new):
        item["state"], item["reason"] = "safe", "Only comments or commented-out options differ."
    else:
        old = default_lookup(target)
        if old is not None and effective(old) == effective(cur):
            item["state"], item["reason"] = "safe", "You made no changes; the package brings new defaults."
        else:
            item["state"] = "custom"
            item["reason"] = "Contains your own changes – review before taking anything over."
    return item


# --- diff for the in-app view -----------------------------------------------
def diff_rows(a, b, title, label_a, label_b):
    """Unified diff as rows {t: head|hunk|del|add|ctx, s: text}; head rows
    carry the labels of both sides (a = "−", b = "+")."""
    rows = [{"t": "head", "s": title, "a": label_a, "b": label_b}]
    lines = list(difflib.unified_diff(a.splitlines(), b.splitlines(), lineterm="", n=3))[2:]
    if not lines:
        rows.append({"t": "ctx", "s": "  (no differences)"})
    for l in lines:
        t = "hunk" if l.startswith("@@") else "del" if l.startswith("-") else "add" if l.startswith("+") else "ctx"
        rows.append({"t": t, "s": l})
    return rows


def backup_name(target, today=None):
    base = f"{target}.vardr-{(today or datetime.date.today()).isoformat()}.bak"
    if not os.path.exists(base):
        return base
    return f"{target}.vardr-{datetime.datetime.now().strftime('%Y-%m-%d-%H%M%S')}.bak"


def adopt_script(paths):
    """Root shell script: save the current file, move the .pacnew into place."""
    lines = ["set -e"]
    for p in paths:
        t = target_of(p)
        q, qt = shlex.quote(p), shlex.quote(t)
        if os.path.exists(t):
            b = shlex.quote(backup_name(t))
            lines.append(f"cp -a -- {qt} {b}")
            lines.append(f"mv -f -- {q} {qt}")
            lines.append(f"echo {shlex.quote(f'{t}: new version in place, old one saved as ')}{b}")
        else:
            lines.append(f"mv -f -- {q} {qt}")
            lines.append(f"echo {shlex.quote(f'{t}: new version in place')}")
    return "\n".join(lines)


def delete_script(paths):
    return "set -e\n" + "\n".join(
        f"rm -f -- {shlex.quote(p)} && echo {shlex.quote('deleted ' + p)}" for p in paths)


class PacFiles(QObject):
    changed = Signal()
    newFiles = Signal(int, str)  # count of fresh files, short list for the notification

    def __init__(self, settings, parent=None):
        super().__init__(parent)
        self.settings = settings
        self._items = []

    def _get_items(self):
        return self._items

    def _get_count(self):
        return len(self._items)

    def _get_safe(self):
        return sum(1 for i in self._items if i["state"] == "safe")

    items = Property("QVariantList", _get_items, notify=changed)
    count = Property(int, _get_count, notify=changed)
    safeCount = Property(int, _get_safe, notify=changed)

    @Slot()
    def scan(self):
        self._items = [classify(p) for p in find_files()]
        self.changed.emit()
        current = [i["path"] for i in self._items]
        seen = set(self.settings.get("pac_notified") or [])
        fresh = [p for p in current if p not in seen]
        self.settings.set("pac_notified", current)
        if fresh:
            names = ", ".join(os.path.basename(p) for p in fresh[:4]) + (" …" if len(fresh) > 4 else "")
            self.newFiles.emit(len(fresh), names)

    def known(self, paths, kinds=None):
        """Only act on files from the last scan (these paths go to root)."""
        ok = {i["path"]: i for i in self._items}
        return [p for p in paths if p in ok and (kinds is None or ok[p]["kind"] in kinds)]

    def safe_paths(self):
        return [i["path"] for i in self._items if i["state"] == "safe"]

    @Slot(str, result="QVariantList")
    def diff(self, path):
        target, kind = target_of(path), kind_of(path)
        other, cur = read(path), read(target) if os.path.exists(target) else ""
        if other is None or cur is None:
            return [{"t": "head", "s": "Not readable without root."}]
        label = "New (.pacnew)" if kind == "pacnew" else f"Saved (.{kind})"
        rows = diff_rows(cur, other, "Current file vs. " + label, "Current (in use)", label)
        item = next((i for i in self._items if i["path"] == path), None)
        if item and item["state"] == "custom":
            # What the user changed comes first: that is what must survive
            old = old_default(target)
            rows = (diff_rows(old, cur, "Your own changes", "Package default (old version)", "Current (in use)")
                    if old is not None else
                    [{"t": "head", "s": "Your own changes", "a": "", "b": ""},
                     {"t": "ctx", "s": "  Previous package version is not in the cache, cannot tell."}]) + rows
        return rows

    @Slot(result=bool)
    def hasMeld(self):
        return bool(shutil.which("meld"))

    @Slot(str)
    def compare(self, path):
        """meld with labelled sides: left = current, right = new/saved."""
        kind = kind_of(path)
        target = target_of(path)
        right = "New (.pacnew)" if kind == "pacnew" else f"Saved (.{kind})"
        QProcess.startDetached("meld", ["--label", f"Current (in use): {target}",
                                        "--label", f"{right}: {path}", target, path])
