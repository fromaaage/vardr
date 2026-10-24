"""Read and write repository sections of pacman.conf.

Everything before the first repository stays untouched ([options], comments).
A disabled repository is a commented header written as "#[name]" (no space),
followed by commented directives. Comments directly above a repository move
with it when the order changes."""
import json
import os
import re
import shlex
import subprocess
import tempfile
import time

from PySide6.QtCore import QObject, Property, Signal, Slot

PACMAN_CONF = "/etc/pacman.conf"
HEADER = re.compile(r"^(#?)\[([^\]\s]+)\]\s*$")
DIRECTIVE = re.compile(r"^(#?)\s*(Include|Server|SigLevel|Usage|CacheServer)\s*=\s*(.*?)\s*$")
SIGLEVELS = ["", "Required DatabaseOptional", "Optional TrustAll", "Never"]


def parse(text):
    """Return (preamble_lines, repos, tail_lines).
    repo = {"name", "enabled", "directives": [[key, value]], "leading": [lines]}"""
    preamble, repos, pending = [], [], []
    current = None
    for line in text.splitlines():
        h = HEADER.match(line)
        if h and h.group(2) != "options":
            if current:
                repos.append(current)
            current = {"name": h.group(2), "enabled": not h.group(1),
                       "directives": [], "leading": pending}
            pending = []
            continue
        if current is None:
            preamble.append(line)
            continue
        d = DIRECTIVE.match(line)
        # Directives belong to the repo while no blank/comment line came in between
        if d and not pending and bool(d.group(1)) == (not current["enabled"]):
            current["directives"].append([d.group(2), d.group(3)])
        else:
            pending.append(line)
    if current:
        repos.append(current)
    # Comments after the last repo are kept as tail
    return preamble, repos, pending


def serialize(preamble, repos, tail):
    out = list(preamble)
    for r in repos:
        lead = list(r.get("leading") or [])
        # Exactly one blank line between blocks, also after reordering
        if out and out[-1].strip() == "":
            while lead and lead[0].strip() == "":
                lead.pop(0)
        elif not lead or lead[0].strip() != "":
            lead.insert(0, "")
        out.extend(lead)
        c = "" if r["enabled"] else "#"
        out.append(f"{c}[{r['name']}]")
        for key, value in r["directives"]:
            out.append(f"{c}{key} = {value}")
    out.extend(tail)
    return "\n".join(out) + "\n"


def load(path=PACMAN_CONF):
    with open(path) as f:
        return parse(f.read())


def write_candidate(text):
    """Write the new config to a temp file and validate it with pacman-conf.
    Returns (path, error)."""
    fd, path = tempfile.mkstemp(prefix="garuda-pilot-", suffix=".conf")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(path, 0o644)
    res = subprocess.run(["pacman-conf", "--config", path, "--repo-list"],
                         capture_output=True, text=True)
    if res.returncode != 0:
        os.unlink(path)
        msg = (res.stderr or res.stdout).strip() or "pacman-conf rejected the file"
        return None, msg.replace(path, "pacman.conf")
    return path, ""


KEY_ID = re.compile(r"^[0-9A-Fa-f]{8,40}$")
KEYSERVER = "keyserver.ubuntu.com"


def to_view(repo):
    """Flatten a parsed repo for QML: SigLevel and source shown separately."""
    sig = next((v for k, v in repo["directives"] if k == "SigLevel"), "")
    source = next((f"{k}: {v}" for k, v in repo["directives"] if k in ("Include", "Server")), "")
    return {"name": repo["name"], "active": repo["enabled"], "siglevel": sig,
            "source": source, "key": "",
            "directives": json.dumps([d for d in repo["directives"] if d[0] != "SigLevel"]),
            "leading": json.dumps(repo.get("leading") or [])}


def from_view(item):
    directives = json.loads(item["directives"])
    if item.get("siglevel"):
        directives.insert(0, ["SigLevel", item["siglevel"]])
    return {"name": item["name"], "enabled": bool(item["active"]),
            "directives": directives, "leading": json.loads(item["leading"])}


def save_script(candidate, keys):
    """Root script: backup, import keys, then install the validated config.
    set -e: a failing key import leaves pacman.conf unchanged."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = f"{PACMAN_CONF}.bak-{stamp}"
    lines = ["set -e", f"cp -a {PACMAN_CONF} {backup}", f"echo 'Backup: {backup}'"]
    for k in keys:
        lines.append(f"pacman-key --recv-keys {k} --keyserver {KEYSERVER}")
        lines.append(f"pacman-key --lsign-key {k}")
    lines.append(f"install -m644 -o root -g root {shlex.quote(candidate)} {PACMAN_CONF}")
    lines.append(f"rm -f {shlex.quote(candidate)}")
    lines.append("echo 'pacman.conf saved.'")
    return "\n".join(lines)


class RepoEditor(QObject):
    """QML bridge: load() gives a list for a ListModel, prepare() validates
    the edited list and returns a root script (or an error)."""

    errorChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._preamble, self._tail = [], []
        self._error = ""

    def _get_error(self):
        return self._error

    error = Property(str, _get_error, notify=errorChanged)

    def _set_error(self, text):
        self._error = text
        self.errorChanged.emit()

    @Slot(result="QVariantList")
    def load(self):
        self._preamble, repos, self._tail = load()
        self._set_error("")
        return [to_view(r) for r in repos]

    @Slot(result="QVariantList")
    def sigLevels(self):
        return SIGLEVELS

    @Slot(str, str, str, str, result="QVariant")
    def newRepo(self, name, kind, value, siglevel):
        """Build a list item for a new repo, or return an error string."""
        name, value = name.strip(), value.strip()
        if not re.fullmatch(r"[A-Za-z0-9._-]+", name) or name == "options":
            return "Invalid name (letters, digits, . _ - only)."
        if not value:
            return "Server URL or Include path is missing."
        if kind == "Include" and not os.path.isfile(value):
            return f"File not found: {value}"
        return to_view({"name": name, "enabled": True, "leading": [],
                        "directives": ([["SigLevel", siglevel]] if siglevel else []) + [[kind, value]]})

    @Slot("QVariantList", result=str)
    def prepare(self, items):
        names = [i["name"] for i in items]
        dupes = sorted({n for n in names if names.count(n) > 1})
        if dupes:
            self._set_error("Duplicate repository: " + ", ".join(dupes))
            return ""
        keys = []
        for i in items:
            k = (i.get("key") or "").replace(" ", "")
            if k and not KEY_ID.match(k):
                self._set_error(f"Invalid key ID for {i['name']}: {k}")
                return ""
            if k:
                keys.append(k)
        text = serialize(self._preamble, [from_view(i) for i in items], self._tail)
        path, err = write_candidate(text)
        if err:
            self._set_error(err)
            return ""
        self._set_error("")
        return save_script(path, keys)

    @Slot(result=str)
    def rawText(self):
        with open(PACMAN_CONF) as f:
            return f.read()

    @Slot(str, result=str)
    def prepareRaw(self, text):
        """Text mode: validate the whole file with pacman-conf, no key import."""
        path, err = write_candidate(text if text.endswith("\n") else text + "\n")
        self._set_error(err)
        return save_script(path, []) if path else ""


MIRRORLISTS = [  # (rate-mirrors target, file)
    ("arch", "/etc/pacman.d/mirrorlist"),
    ("chaotic-aur", "/etc/pacman.d/chaotic-mirrorlist"),
    ("cachyos", "/etc/pacman.d/cachyos-mirrorlist"),
]
CACHYOS_VARIANTS = ["v3", "v4"]  # derived from cachyos-mirrorlist via $arch_vN


def mirrors_script():
    """Root script: rank mirrors per list; a list is only replaced when the
    new one contains servers. Old list kept as <file>.garuda-pilot.bak."""
    lines = ['replace() { cp -a "$2" "$2.garuda-pilot.bak"; install -m644 "$1" "$2"; '
             'echo "   $(grep -c \'^Server\' "$2") mirrors -> $2"; }']
    for target, path in MIRRORLISTS:
        if not os.path.isfile(path):
            continue
        lines += [
            f"echo '--> {target}'",
            "tmp=$(mktemp)",
            f"if rate-mirrors --allow-root --save=\"$tmp\" {target} >/dev/null "
            f"&& grep -q '^Server' \"$tmp\"; then replace \"$tmp\" {path}; "
            "else echo '   failed, old list kept'; fi",
            'rm -f "$tmp"',
        ]
    base = "/etc/pacman.d/cachyos-mirrorlist"
    for v in CACHYOS_VARIANTS:
        path = f"/etc/pacman.d/cachyos-{v}-mirrorlist"
        if os.path.isfile(base) and os.path.isfile(path):
            lines += [
                f"echo '--> cachyos-{v}'",
                "tmp=$(mktemp)",
                f"sed 's|/\\$arch/|/$arch_{v}/|' {base} > \"$tmp\"",
                f"replace \"$tmp\" {path}",
                'rm -f "$tmp"',
            ]
    return "\n".join(lines)
