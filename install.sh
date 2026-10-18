#!/usr/bin/env bash
set -e

# ==============================================================================
# kwin-scroll-daemon Universal Installer (KDE Plasma 6 / Wayland)
# ==============================================================================

BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
KWIN_SCRIPT_DIR="${HOME}/.local/share/kwin/scripts/scroll-window-tracker"

echo "==> Checking runtime dependencies..."
MISSING=0
python3 -c "import dbus, gi; from gi.repository import GLib, Gio" 2>/dev/null || MISSING=1

if [ $MISSING -eq 1 ]; then
    echo "[-] Required Python libraries missing (dbus, gi / gobject)."
    echo "    Please install them for your distribution:"
    echo "      • Fedora/RHEL:   sudo dnf install python3-dbus python3-gobject"
    echo "      • Arch/Manjaro:  sudo pacman -S python-dbus python-gobject"
    echo "      • openSUSE:      sudo zypper install python3-dbus-python python3-gobject"
    echo "      • Ubuntu/Debian: sudo apt install python3-dbus python3-gi"
    exit 1
fi

echo "==> Creating local user directories..."
mkdir -p "${BIN_DIR}" "${CONFIG_DIR}" "${SYSTEMD_USER_DIR}" "${KWIN_SCRIPT_DIR}/contents/code"

echo "==> Installing KWin window tracker script..."
cat << 'EOF' > "${KWIN_SCRIPT_DIR}/metadata.json"
{
    "KPackageStructure": "KWin/Script",
    "KPlugin": {
        "Authors": [{ "Name": "Community" }],
        "Description": "Tracks active/hovered window class for scroll speed adjustments",
        "Icon": "preferences-system-windows-script-test",
        "Id": "scroll-window-tracker",
        "License": "GPLv3",
        "Name": "Scroll Window Tracker",
        "Version": "1.0"
    },
    "X-KDE-PluginKeyword": "scroll-window-tracker",
    "X-Plasma-API": "javascript",
    "X-Plasma-MainScript": "code/main.js"
}
EOF

cat << 'EOF' > "${KWIN_SCRIPT_DIR}/contents/code/main.js"
let lastAppClass = "";

function notifyWindow(win) {
    if (!win) return;

    let cls = "";
    try {
        if (win.resourceClass && win.resourceClass.length > 0) {
            cls = win.resourceClass.toString();
        } else if (win.desktopFileName && win.desktopFileName.length > 0) {
            cls = win.desktopFileName.toString();
        } else if (win.caption && win.caption.length > 0) {
            cls = win.caption.toString();
        }
    } catch (e) {
        return;
    }

    if (!cls || cls === lastAppClass) return;
    lastAppClass = cls;

    callDBus(
        "org.kde.ScrollSpeedDaemon",
        "/Manager",
        "org.kde.ScrollSpeedDaemon",
        "SetWindowContext",
        cls
    );
}

// 1. Hook window clicks / focus activation
workspace.windowActivated.connect(function(win) {
    notifyWindow(win);
});

// 2. Hook pointer movement via official Plasma 6 windowAt
workspace.cursorPosChanged.connect(function() {
    try {
        let pos = workspace.cursorPos;
        if (!pos) return;

        let wins = workspace.windowAt(pos, 1);
        if (wins && wins.length > 0) {
            notifyWindow(wins[0]);
        }
    } catch (err) {}
});
EOF

echo "==> Enabling KWin script in Plasma..."
kwriteconfig6 --file kwinrc --group Plugins --key scroll-window-trackerEnabled false 2>/dev/null || true
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null || true
sleep 1
kwriteconfig6 --file kwinrc --group Plugins --key scroll-window-trackerEnabled true 2>/dev/null || true
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null || true

echo "==> Installing Python daemon..."
cat << 'EOF' > "${BIN_DIR}/kwin_scroll_daemon.py"
#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib, Gio

CONFIG_PATH = Path.home() / ".config" / "kwin-scroll-rules.json"

class RuleEngine:
    def __init__(self, config_file: Path):
        self.config_file = config_file
        self.rules = []
        self.default_factor = 1.0
        self.load()

    def load(self):
        if not self.config_file.exists():
            return
        try:
            with open(self.config_file, "r") as f:
                data = json.load(f)
            self.default_factor = float(data.get("default_factor", 1.0))
            self.rules = [
                (re.compile(item["match"], re.IGNORECASE), float(item["factor"]))
                for item in data.get("rules", [])
                if "match" in item and "factor" in item
            ]
            print(f"[Rules] Loaded {len(self.rules)} rules. Default: {self.default_factor}")
        except Exception as e:
            print(f"[Rules] Error reading config: {e}", file=sys.stderr)

    def match(self, app_class: str) -> float:
        for pattern, factor in self.rules:
            if pattern.search(app_class):
                return factor
        return self.default_factor

def find_touchpad_device_path(session_bus):
    for i in range(32):
        path = f"/org/kde/KWin/InputDevice/event{i}"
        try:
            dev = session_bus.get_object("org.kde.KWin", path)
            props = dbus.Interface(dev, "org.freedesktop.DBus.Properties")
            dev_name = str(props.Get("org.kde.KWin.InputDevice", "name")).lower()
            if "touchpad" in dev_name or "trackpad" in dev_name:
                print(f"[Input] Identified touchpad: {dev_name} at {path}")
                return path
        except dbus.DBusException:
            continue
    return None

class ScrollService(dbus.service.Object):
    def __init__(self, bus, engine, touchpad_props):
        bus_name = dbus.service.BusName("org.kde.ScrollSpeedDaemon", bus=bus)
        super().__init__(bus_name, "/Manager")
        self.engine = engine
        self.touchpad_props = touchpad_props
        self.current_factor = None

    @dbus.service.method("org.kde.ScrollSpeedDaemon", in_signature="s")
    def SetWindowContext(self, app_class):
        factor = self.engine.match(app_class)
        if factor != self.current_factor:
            self.current_factor = factor
            try:
                self.touchpad_props.Set(
                    "org.kde.KWin.InputDevice", 
                    "scrollFactor", 
                    dbus.Double(factor)
                )
                print(f"[Scroll] Window: '{app_class}' -> scrollFactor: {factor}")
            except dbus.DBusException as e:
                print(f"[Scroll] Failed to update scrollFactor: {e}", file=sys.stderr)

def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    tp_path = find_touchpad_device_path(bus)
    if not tp_path:
        print("[Error] No touchpad found under KWin InputDevices.", file=sys.stderr)
        sys.exit(1)

    tp_obj = bus.get_object("org.kde.KWin", tp_path)
    tp_props = dbus.Interface(tp_obj, "org.freedesktop.DBus.Properties")

    engine = RuleEngine(CONFIG_PATH)
    service = ScrollService(bus, engine, tp_props)

    if CONFIG_PATH.exists():
        gfile = Gio.File.new_for_path(str(CONFIG_PATH))
        monitor = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
        monitor.connect("changed", lambda *_: engine.load())

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        tp_props.Set("org.kde.KWin.InputDevice", "scrollFactor", dbus.Double(1.0))

if __name__ == "__main__":
    main()
EOF
chmod +x "${BIN_DIR}/kwin_scroll_daemon.py"

if [ ! -f "${CONFIG_DIR}/kwin-scroll-rules.json" ]; then
    echo "==> Creating default configuration at ~/.config/kwin-scroll-rules.json..."
    cat << 'EOF' > "${CONFIG_DIR}/kwin-scroll-rules.json"
{
  "default_factor": 1.0,
  "rules": [
    { "match": "brave|brave-browser|com\.brave\.Browser", "factor": 0.35 },
    { "match": "google-chrome|chromium", "factor": 0.35 },
    { "match": "firefox|org\.mozilla\.firefox", "factor": 0.40 },
    { "match": "code", "factor": 0.40 },
    { "match": "slack|discord", "factor": 0.50 },
    { "match": "org\.kde\.okular", "factor": 1.40 },
    { "match": "kitty|alacritty|konsole", "factor": 0.85 }
  ]
}
EOF
else
    echo "==> Preserving existing configuration at ~/.config/kwin-scroll-rules.json"
fi

echo "==> Installing systemd user service..."
cat << 'EOF' > "${SYSTEMD_USER_DIR}/kwin-scroll-daemon.service"
[Unit]
Description=KDE Plasma Touchpad Per-Application Scroll Speed Daemon
After=plasma-core.target graphical-session.target

[Service]
Environment=PYTHONUNBUFFERED=1
ExecStart=%h/.local/bin/kwin_scroll_daemon.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

echo "==> Starting and enabling daemon via systemd..."
systemctl --user daemon-reload
systemctl --user enable --now kwin-scroll-daemon.service

echo ""
echo "===================================================================="
echo "Installation Successful!"
echo "• Daemon is running and enabled across logins."
echo "• Config: ~/.config/kwin-scroll-rules.json (hot-reloaded on save)"
echo "• Monitor logs: journalctl --user -u kwin-scroll-daemon.service -f"
echo "===================================================================="
