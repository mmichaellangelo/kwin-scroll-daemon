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
