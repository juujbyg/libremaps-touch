/* Developer test hook -- ONLY in builds made with ./build.sh --dev.
 * Polls <config>/hook.js; evaluates it in the app's scope and writes the
 * result to <config>/hook.out. Needs QML_XHR_ALLOW_FILE_READ/WRITE=1. */
import QtQuick 2.0

Item {
    id: hook
    property string dir: ""
    property string lastSeen: ""

    Timer {
        interval: 1200; repeat: true; running: true
        onTriggered: hook.poll()
    }

    function readFile(path) {
        var x = new XMLHttpRequest();
        x.open("GET", "file://" + path, false);
        try { x.send(); } catch (e) { return ""; }
        return x.responseText || "";
    }
    function writeFile(path, text) {
        var x = new XMLHttpRequest();
        x.open("PUT", "file://" + path, false);
        try { x.send(text); } catch (e) { console.log("hook write failed " + e); }
    }
    function poll() {
        if (!dir) { try { dir = py.evaluate("poor.paths.CONFIG_HOME_DIR"); } catch (e) { return; } }
        var src = readFile(dir + "/hook.js");
        if (!src || src === lastSeen) return;
        lastSeen = src;
        var out;
        try { out = String(eval(src)); } catch (e) { out = "EXC: " + e + " @" + e.lineNumber; }
        writeFile(dir + "/hook.out", out);
    }
}
