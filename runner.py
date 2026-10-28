"""Runs shell commands in a pseudo-terminal and streams their output to QML."""
import codecs
import fcntl
import html
import os
import pty
import re
import struct
import subprocess
import termios

from PySide6.QtCore import QObject, QSocketNotifier, Property, Signal, Slot

CSI = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|\x0f|\x0e")
# Unfinished line that waits for an answer: "[Y/n]", "? ", "): ", "==> "
PROMPT = re.compile(r"(\[[yYnN]/[yYnN]\]|\?|:|==>)\s*$")

COLS, ROWS = 110, 40
# Installed root helper with a polkit rule that remembers the password for a
# few minutes (packaging/polkit). Without it every root step asks again.
ROOT_HELPER = "/usr/lib/vardr/vardr-root"
SUDO_WRAPPER = "/usr/lib/vardr/vardr-sudo"


def helper_installed():
    return os.access(ROOT_HELPER, os.X_OK)

COLORS = {
    30: "#8e8e93", 31: "#ff453a", 32: "#30d158", 33: "#ffd60a",
    34: "#0a84ff", 35: "#bf5af2", 36: "#64d2ff", 37: "#e5e5ea",
}
for _c in range(30, 38):
    COLORS[_c + 60] = COLORS[_c]


def ansi_to_html(text):
    """Convert SGR color codes to <span>, drop all other escape sequences."""
    text = OSC.sub("", text)
    out, pos, color, bold, open_span = [], 0, None, False, False
    for m in CSI.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        pos = m.end()
        if m.group(2) != "m":
            continue
        for code in [int(c) if c.isdigit() else 0 for c in m.group(1).split(";")]:
            if code == 0:
                color, bold = None, False
            elif code == 1:
                bold = True
            elif code == 22:
                bold = False
            elif code in COLORS:
                color = COLORS[code]
            elif code == 39:
                color = None
        if open_span:
            out.append("</span>")
            open_span = False
        if color or bold:
            style = (f"color:{color};" if color else "") + ("font-weight:600;" if bold else "")
            out.append(f'<span style="{style}">')
            open_span = True
    out.append(html.escape(text[pos:]))
    if open_span:
        out.append("</span>")
    return "".join(out)


def _take_tty():
    """Child side: make the pty the controlling terminal (for Ctrl+C)."""
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def strip_ansi(text):
    return CSI.sub("", OSC.sub("", text))


TOKEN = re.compile(r"(\x1b\[[0-9;?]*[A-Za-z]|\r|\n)")
PARTIAL = re.compile(r"\x1b(\[[0-9;?]*)?$")
HTML_MARK = "\x00"  # rows starting with this are ready-made HTML (notes)


class Screen:
    """Minimal terminal: rows that can be rewritten via \\r and cursor moves
    (pacman's parallel downloads jump up and down with ESC[nF / ESC[nE).
    Text written at column 0 replaces the row, later text is appended."""

    def __init__(self):
        self.rows = []
        self.row = 0
        self.col0 = True
        self.dirty = set()

    def newline(self):
        """Start a fresh row below everything written so far."""
        if self.rows and self.rows[-1] == "":
            self.row = len(self.rows) - 1
        else:
            self.row = len(self.rows)
        self.col0 = True

    def add_line(self, text):
        self.newline()
        self._write(text)
        self.row += 1
        self.col0 = True

    def feed(self, text):
        for tok in TOKEN.split(text):
            if not tok:
                continue
            if tok == "\r":
                self.col0 = True
            elif tok == "\n":
                self.row += 1
                self.col0 = True
            elif tok.startswith("\x1b["):
                n = int(tok[2:-1]) if tok[2:-1].isdigit() else 1
                cmd = tok[-1]
                if cmd == "m":
                    self._write(tok)
                elif cmd in "FA":
                    self.row = max(0, self.row - n)
                    self.col0 = self.col0 or cmd == "F"
                elif cmd in "EB":
                    self.row += n
                    self.col0 = self.col0 or cmd == "E"
                elif cmd == "K" and self.col0:
                    self._set("")
            else:
                self._write(tok)

    def _write(self, text):
        if self.col0:
            self._set(text)
            self.col0 = False
        else:
            self._set(self._get() + text)

    def _get(self):
        return self.rows[self.row] if self.row < len(self.rows) else ""

    def _set(self, text):
        while len(self.rows) <= self.row:
            self.rows.append("")
            self.dirty.add(len(self.rows) - 1)
        self.rows[self.row] = text
        self.dirty.add(self.row)

    def current(self):
        """Unfinished text at the cursor (for prompt detection)."""
        return "" if self.col0 else self._get()

    def take_dirty(self):
        d, self.dirty = sorted(self.dirty), set()
        return d


class Runner(QObject):
    """One command at a time. Output lives in a Screen; changed rows are
    sent as rowChanged(index, html) so progress bars update in place."""

    rowChanged = Signal(int, str)
    cleared = Signal()
    promptChanged = Signal()
    runningChanged = Signal()
    finished = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._proc = None
        self._fd = None
        self._notifier = None
        self._buf = ""
        self._decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self._screen = Screen()
        self._prompt = ""
        self._cols = COLS

    # --- properties -----------------------------------------------------
    def _get_prompt(self):
        return self._prompt

    def _get_running(self):
        return self._proc is not None

    prompt = Property(str, _get_prompt, notify=promptChanged)
    running = Property(bool, _get_running, notify=runningChanged)

    @Slot(int)
    def setColumns(self, cols):
        """Terminal width follows the log view; resizes a running process too."""
        self._cols = max(40, min(300, cols))
        if self._fd is not None:
            fcntl.ioctl(self._fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, self._cols, 0, 0))

    # --- log ------------------------------------------------------------
    @Slot()
    def clear(self):
        self._screen = Screen()
        self.cleared.emit()

    def note(self, text, color=None):
        """Add an informational line (not from the process)."""
        esc = html.escape(text)
        self._screen.add_line(HTML_MARK + (f'<span style="color:{color};">{esc}</span>' if color else esc))
        self._flush()

    @Slot(result=str)
    def plainText(self):
        return "\n".join(html.unescape(re.sub(r"<[^>]+>", "", strip_ansi(r.lstrip(HTML_MARK))))
                         for r in self._screen.rows)

    def _flush(self):
        for i in self._screen.take_dirty():
            row = self._screen.rows[i]
            self.rowChanged.emit(i, row[1:] if row.startswith(HTML_MARK) else ansi_to_html(row))

    # --- control --------------------------------------------------------
    def start(self, command, as_root=False, env=None, display=None):
        """Run `command` through bash. as_root wraps it in pkexec.
        `display` replaces the command in the log header."""
        if self._proc:
            return False
        argv = ["/bin/bash", "-c", command]
        if as_root:
            argv = (["pkexec", ROOT_HELPER, "--sh", command] if helper_installed()
                    else ["pkexec", "env", "TERM=xterm-256color"] + argv)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, self._cols, 0, 0))
        full_env = dict(os.environ, TERM="xterm-256color", COLUMNS=str(self._cols), LINES=str(ROWS))
        full_env.update(env or {})
        self.note("$ " + (display or command), "#8e8e93")
        try:
            self._proc = subprocess.Popen(
                argv, stdin=slave, stdout=slave, stderr=slave,
                env=full_env, start_new_session=True, close_fds=True,
                preexec_fn=_take_tty)
        except OSError as e:
            os.close(master)
            os.close(slave)
            self.note(str(e), "#ff453a")
            self.finished.emit(127)
            return False
        os.close(slave)
        self._fd = master
        self._screen.newline()
        self._notifier = QSocketNotifier(master, QSocketNotifier.Read, self)
        self._notifier.activated.connect(self._read)
        self.runningChanged.emit()
        return True

    @Slot(str)
    def send(self, text):
        if self._fd is not None:
            os.write(self._fd, (text + "\n").encode())
            self._set_prompt("")

    @Slot()
    def stop(self):
        # Ctrl+C through the tty also reaches processes running as root
        if self._fd is not None:
            os.write(self._fd, b"\x03")

    # --- internals ------------------------------------------------------
    def _read(self):
        try:
            data = os.read(self._fd, 65536)
        except OSError:
            data = b""
        if not data:
            self._close()
            return
        self.feed(self._decoder.decode(data))

    def feed(self, text):
        """Process terminal output (also used by tests)."""
        text = OSC.sub("", self._buf + text)
        m = PARTIAL.search(text)  # escape sequence cut off at chunk end
        self._buf = text[m.start():] if m else ""
        self._screen.feed(text[:m.start()] if m else text)
        self._flush()
        plain = strip_ansi(self._screen.current()).strip()
        self._set_prompt(plain if plain and PROMPT.search(plain) else "")

    def _set_prompt(self, text):
        if text != self._prompt:
            self._prompt = text
            self.promptChanged.emit()

    def _close(self):
        if self._notifier:
            self._notifier.setEnabled(False)
            self._notifier = None
        if self._fd is not None:
            os.close(self._fd)
            self._fd = None
        self._buf = ""
        self._set_prompt("")
        code = self._proc.wait() if self._proc else 0
        self._proc = None
        self.runningChanged.emit()
        self.finished.emit(code)
