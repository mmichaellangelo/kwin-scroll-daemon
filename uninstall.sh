#!/usr/bin/env bash
set -e

# ==============================================================================
# kwin-scroll-daemon Uninstaller
# ==============================================================================

echo "==> Stopping and disabling systemd service..."
systemctl --user stop kwin-scroll-daemon.service 2>/dev/null || true
systemctl --user disable kwin-scroll-daemon.service 2>/dev/null || true
rm -f "${HOME}/.config/systemd/user/kwin-scroll-daemon.service"
systemctl --user daemon-reload

echo "==> Disabling and removing KWin tracker script..."
kwriteconfig6 --file kwinrc --group Plugins --key scroll-window-trackerEnabled false 2>/dev/null || true
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null || true
rm -rf "${HOME}/.local/share/kwin/scripts/scroll-window-tracker"

echo "==> Removing daemon binary..."
rm -f "${HOME}/.local/bin/kwin_scroll_daemon.py"

echo ""
echo "Uninstallation complete. Custom rules at ~/.config/kwin-scroll-rules.json were kept."
