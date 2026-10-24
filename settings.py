"""Settings stored as JSON in ~/.config/garuda-pilot/settings.json."""
import json
import os

from PySide6.QtCore import QObject, Signal, Slot

CONFIG_DIR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "garuda-pilot")
PATH = os.path.join(CONFIG_DIR, "settings.json")

DEFAULTS = {
    "update_command": "garuda-update",
    "update_as_root": True,
    "aur_helper": "auto",
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

    @Slot(str)
    def reset(self, key):
        self.set(key, DEFAULTS[key])
