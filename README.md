# kwin-scroll-daemon

Dynamic, hover-aware per-application touchpad scroll multiplier daemon for **KDE Plasma 6 (Wayland)**.

## Compatibility
Works on any Linux distribution running KDE Plasma 6 on Wayland (Fedora, Arch Linux, openSUSE, Debian, Kubuntu, KDE neon, etc.).

## Quick Installation

```bash
chmod +x install.sh
./install.sh
```

The script automatically detects dependencies, installs the background daemon and KWin script, and enables autostart via systemd.

## Customizing Rules

Edit `~/.config/kwin-scroll-rules.json` anytime. The daemon automatically hot-reloads the file when saved—no restart required.

## Live Log Stream

```bash
journalctl --user -u kwin-scroll-daemon.service -f
```

## Uninstallation

```bash
chmod +x uninstall.sh
./uninstall.sh
```
