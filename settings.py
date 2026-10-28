"""Settings stored as JSON in ~/.config/vardr/settings.json."""
import json
import os
import shutil

from PySide6.QtCore import QObject, Signal, Slot

CONFIG_DIR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "vardr")
PATH = os.path.join(CONFIG_DIR, "settings.json")

GARUDA_FIX = "garuda-health --fix; if command -v limine-update >/dev/null; then limine-update; fi"


def detect_defaults(which=shutil.which):
    """Garuda tools if present, plain pacman otherwise. No fix command without garuda-health."""
    return {
        "update_command": "garuda-update" if which("garuda-update") else "pacman -Syu",
        "fix_command": GARUDA_FIX if which("garuda-health") else "",
    }


DEFAULTS = {
    **detect_defaults(),
    "update_as_root": True,
    "aur_helper": "auto",
    "cache_keep": 2,
    "fix_as_root": True,
    "fix_in_update_all": False,
    "check_interval": 24,  # hours, 0 = off
    "check_aur": True,
    "autostart": True,
    "last_check": 0,
    "notified": [],
    "appearance": "",          # "", "dark" or "light" (choice made in the app)
    "appearance_desktop": "",  # desktop mode when the app last ran
}


class Settings(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._data = dict(DEFAULTS)
        try:
            with open(PATH) as f:
                self._data.update(json.load(f))
        except (OSError, ValueError):
            pass

    @Slot(str, result="QVariant")
    def get(self, key):
        return self._data.get(key, DEFAULTS.get(key))

    @Slot(str, "QVariant")
    def set(self, key, value):
        if self._data.get(key) == value:
            return
        self._data[key] = value
        os.makedirs(CONFIG_DIR, exist_ok=True)
        tmp = PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self._data, f, indent=2)
        os.replace(tmp, PATH)
        self.changed.emit()

    @Slot(str, result="QVariant")
    def defaultValue(self, key):
        return DEFAULTS.get(key)

    @Slot(str, result=bool)
    def isDefault(self, key):
        return self.get(key) == DEFAULTS.get(key)

    @Slot(str)
    def reset(self, key):
        self.set(key, DEFAULTS[key])
