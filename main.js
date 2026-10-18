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

workspace.windowActivated.connect(function(win) {
    notifyWindow(win);
});

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
