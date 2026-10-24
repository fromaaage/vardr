"""Runs shell commands in a pseudo-terminal and streams their output to QML."""
import fcntl
import html
import os
import pty
import re
import subprocess
import termios

from PySide6.QtCore import QObject, QSocketNotifier, Property, Signal, Slot

CSI = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|\x0f|\x0e")
# Unfinished line that waits for an answer: "[Y/n]", "? ", "): ", "==> "
PROMPT = re.compile(r"(\[[yYnN]/[yYnN]\]|\?|:|==>)\s*$")

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


class Runner(QObject):
    """One command at a time. Lines go to lineAdded, the unfinished line
    (progress bars, questions) to currentLine."""

    lineAdded = Signal(str)
    currentLineChanged = Signal()
    promptChanged = Signal()
    runningChanged = Signal()
    finished = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._proc = None
        self._fd = None
        self._notifier = None
        self._buf = ""
        self._current = ""
        self._prompt = ""

    # --- properties -----------------------------------------------------
    def _get_current(self):
        return ansi_to_html(self._current)

    def _get_prompt(self):
        return self._prompt

    def _get_running(self):
        return self._proc is not None

    currentLine = Property(str, _get_current, notify=currentLineChanged)
    prompt = Property(str, _get_prompt, notify=promptChanged)
    running = Property(bool, _get_running, notify=runningChanged)

    # --- control --------------------------------------------------------
    def start(self, command, as_root=False, env=None, display=None):
        """Run `command` through bash. as_root wraps it in pkexec.
        `display` replaces the command in the log header."""
        if self._proc:
            return False
        argv = ["/bin/bash", "-c", command]
        if as_root:
            argv = ["pkexec", "env", "TERM=xterm-256color"] + argv
        master, slave = pty.openpty()
        full_env = dict(os.environ, TERM="xterm-256color", COLUMNS="110", LINES="40")
        full_env.update(env or {})
        self.lineAdded.emit(f'<span style="color:#8e8e93;">$ {html.escape(display or command)}</span>')
        try:
            self._proc = subprocess.Popen(
                argv, stdin=slave, stdout=slave, stderr=slave,
                env=full_env, start_new_session=True, close_fds=True,
                preexec_fn=_take_tty)
        except OSError as e:
            os.close(master)
            os.close(slave)
            self.lineAdded.emit(f'<span style="color:#ff453a;">{html.escape(str(e))}</span>')
            self.finished.emit(127)
            return False
        os.close(slave)
        self._fd = master
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
        self._buf += data.decode("utf-8", "replace")
        *lines, self._buf = self._buf.split("\n")
        for line in lines:
            line = line.rstrip("\r")
            if "\r" in line:  # progress bar: keep only the last redraw
                line = line.rsplit("\r", 1)[-1]
            self.lineAdded.emit(ansi_to_html(line))
        self._current = self._buf.rsplit("\r", 1)[-1]
        self.currentLineChanged.emit()
        plain = strip_ansi(self._current).strip()
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
        if self._current:
            self.lineAdded.emit(ansi_to_html(self._current))
        self._buf = self._current = ""
        self.currentLineChanged.emit()
        self._set_prompt("")
        code = self._proc.wait() if self._proc else 0
        self._proc = None
        self.runningChanged.emit()
        self.finished.emit(code)
