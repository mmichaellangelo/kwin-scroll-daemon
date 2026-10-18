Name:           kwin-scroll-daemon
Version:        1.0.0
Release:        1%{?dist}
Summary:        Per-application touchpad scroll speed multiplier daemon for KDE Plasma 6

License:        GPL-3.0-or-later
URL:            https://github.com/local/kwin-scroll-daemon
BuildArch:      noarch

Source0:        kwin_scroll_daemon.py
Source1:        kwin-scroll-rules.json
Source2:        kwin-scroll-daemon.service
Source3:        metadata.json
Source4:        main.js

Requires:       python3
Requires:       python3-dbus
Requires:       python3-gobject
Requires:       kwin
Requires:       plasma-workspace

%description
A lightweight background daemon and KWin script that dynamically scales
touchpad scroll speed on KDE Plasma 6 (Wayland) based on the active or
hovered application window.

%prep
# Nothing to unpack

%build
# Pure scripts, no compilation needed

%install
rm -rf %{buildroot}

install -D -p -m 0755 %{SOURCE0} %{buildroot}%{_bindir}/kwin_scroll_daemon.py
install -D -p -m 0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/xdg/kwin-scroll-rules.json
install -D -p -m 0644 %{SOURCE2} %{buildroot}%{_userunitdir}/kwin-scroll-daemon.service
install -D -p -m 0644 %{SOURCE3} %{buildroot}%{_datadir}/kwin/scripts/scroll-window-tracker/metadata.json
install -D -p -m 0644 %{SOURCE4} %{buildroot}%{_datadir}/kwin/scripts/scroll-window-tracker/contents/code/main.js

%post
if [ $1 -eq 1 ]; then
    echo "=================================================================="
    echo "kwin-scroll-daemon installed successfully!"
    echo "To activate for your user session, run:"
    echo "  kwriteconfig6 --file kwinrc --group Plugins --key scroll-window-trackerEnabled true"
    echo "  busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure"
    echo "  systemctl --user enable --now kwin-scroll-daemon.service"
    echo "=================================================================="
fi

%preun
if [ $1 -eq 0 ]; then
    systemctl --user --global stop kwin-scroll-daemon.service 2>/dev/null || true
    systemctl --user --global disable kwin-scroll-daemon.service 2>/dev/null || true
fi

%files
%{_bindir}/kwin_scroll_daemon.py
%config(noreplace) %{_sysconfdir}/xdg/kwin-scroll-rules.json
%{_userunitdir}/kwin-scroll-daemon.service
%{_datadir}/kwin/scripts/scroll-window-tracker/metadata.json
%{_datadir}/kwin/scripts/scroll-window-tracker/contents/code/main.js

%changelog
* Sun Oct 18 2026 Developer <dev@local> - 1.0.0-1
- Initial RPM package release
