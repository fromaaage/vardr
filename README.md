<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="icons/wordmark-dark.svg">
    <img src="icons/wordmark-light.svg" alt="varðr" height="72">
  </picture>
</p>

<p align="center"><b>The update guardian for Arch-based systems.</b><br>
One-click updates, AUR, cache cleaning, mirrors and repositories – with a tray icon that tells you when updates are waiting.</p>

<p align="center"><sub>In Norse myth, a <i>vörðr</i> is a guardian spirit that watches over a person. Pronounced “var-thr”.</sub></p>

![varðr](docs/screenshot-dark.png)

## Features

- **Update all**: system update → AUR → cache cleaning in one run, stops at the first failing step
- **Custom update command**: defaults to `garuda-update` on Garuda Linux, `pacman -Syu` elsewhere; optionally run as root via pkexec
- **AUR updates** with paru or yay, run as your user (`-Sua --sudo pkexec`)
- **Cache cleaning** with `paccache`: keep the last 1–3 versions, drop uninstalled packages; pacman cache and AUR build directories
- **Fix command** (optional; on Garuda `garuda-health --fix`, followed by `limine-update` if installed), optionally as last step of Update all
- **One password per run** thanks to a polkit rule (see Notes)
- **Repository editor** for `/etc/pacman.conf`: enable/disable, reorder by drag, SigLevel, add with key import, remove, raw text mode; validated with `pacman-conf`, timestamped backup, followed by a full update (no partial `-Sy`)
- **Mirror ranking** with `rate-mirrors` for Arch, chaotic-aur and CachyOS (v3/v4 lists derived)
- **Update check** in the background (`checkupdates` + AUR), interval off/1/6/12/24 h, tray badge, notification only for new updates
- Live terminal output with in-place progress bars and Yes/No buttons for prompts
- Light/dark mode following the desktop, with manual override

Works on Arch, Garuda, CachyOS, EndeavourOS and other Arch-based distributions.

![Light mode](docs/screenshot-light.png)

## Requirements

`python`, `pyside6`, `pacman-contrib`, `polkit` (plus a running polkit agent).
Optional: `paru` or `yay`, `rate-mirrors`, `garuda-update`.

## Install

```sh
git clone https://github.com/fromaaage/vardr.git
cd vardr/packaging
makepkg -si
```

Or run from source: `python app.py` (`--tray` starts hidden in the tray).

## Notes

- Root steps run through a small helper (`/usr/lib/vardr/vardr-root`) with a polkit rule that remembers the password for a few minutes, so a full run asks once. From source, install it with `sudo packaging/polkit/install.sh`; without it, every root step asks separately.
- With a system tray, closing the window keeps varðr running. "Start at login" writes `~/.config/autostart/vardr.desktop`.
- Settings: `~/.config/vardr/settings.json`.
- Backups: `/etc/pacman.conf.bak-<timestamp>`, mirror lists as `<file>.vardr.bak`.
- Logo: `packaging/make-logo.py` (Inter Display Black, SIL Open Font License).

*Not affiliated with Arch Linux or the Garuda Linux project.*

## License

MIT
