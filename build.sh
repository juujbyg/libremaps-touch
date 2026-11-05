#!/bin/bash
# Build the Drive fork of Pure Maps (QML/Python only: the native parts are reused
# from the stock package, whose own name is patched in place -- same length).
# Output: package tree in build/pkg (click built on the phone)
set -euo pipefail
cd "$(dirname "$0")"
DEV=0
if [ "${1:-}" = "--dev" ]; then DEV=1; shift; fi
VERSION=${1:-3.5.0-drive3}
OLD=pure-maps.jonnius
NEW=libremaps.juujbyg
rm -rf build/pkg && mkdir -p build/pkg
rsync -a --exclude .click orig/ build/pkg/
# overlay our files over the stock ones
rsync -a overlay/ build/pkg/
# rename the share dir the binary looks for
mv build/pkg/share/$OLD build/pkg/share/$NEW
rsync -a --remove-source-files build/pkg/share/$OLD/ build/pkg/share/$NEW/ 2>/dev/null || true
# the patched binary loads translations/$NEW-<locale>.qm: those come from
# overlay (i18n/build.py) and include Pure Maps' own strings, so drop the old ones
rm -f build/pkg/share/$NEW/translations/$OLD-*.qm
python3 -I - <<PY
import pathlib
p = pathlib.Path("build/pkg/lib/aarch64-linux-gnu/bin/pure-maps")
b = p.read_bytes()
old, new = "$OLD", "$NEW"
assert len(old) == len(new)
n = b.count(old.encode()) + b.count(old.encode("utf-16le"))
b = b.replace(old.encode(), new.encode()).replace(old.encode("utf-16le"), new.encode("utf-16le"))
p.write_bytes(b)
print("patched", n, "occurrences")
PY
# desktop entry, manifest
EXEC="env UBUNTU_UI_TOOLKIT_THEME=Lomiri.Components.Themes.Ambiance QT_QUICK_CONTROLS_STYLE=Default"
if [ "$DEV" = 1 ]; then
  EXEC="$EXEC QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1"
  cp devhook/DevHook.qml build/pkg/share/$NEW/qml/DevHook.qml
  sed -i 's|    ApproxLocation { id: approxLocation }|    ApproxLocation { id: approxLocation }\n    DevHook { id: devHook }|' build/pkg/share/$NEW/qml/RootPage.qml
fi
cat > build/pkg/pure-maps.desktop <<D
[Desktop Entry]
Name=LibreMaps
Exec=$EXEC pure-maps %u
Icon=pure-maps.svg
Type=Application
MimeType=x-scheme-handler/geo
X-Lomiri-Touch=true
D
cat > build/pkg/manifest.json <<M
{
    "architecture": "arm64",
    "description": "LibreMaps: private navigation by walk, bike, car, bus and metro, with a dark driving view, speed limits and camera alerts. Fork of Pure Maps. No account, no ads, no analytics.",
    "framework": "ubuntu-touch-24.04-1.x",
    "hooks": {
        "pure-maps": {
            "apparmor": "pure-maps.apparmor",
            "desktop": "pure-maps.desktop",
            "urls": "app-dispatcher.json"
        }
    },
    "maintainer": "juujbyg <juujbyg@users.noreply.github.com>",
    "name": "$NEW",
    "title": "LibreMaps",
    "version": "$VERSION"
}
M
find build/pkg -name __pycache__ -type d -prune -exec rm -rf {} +
rm -f build/pkg/share/applications/*.desktop 2>/dev/null || true
echo "package tree ready in build/pkg ($(du -sh build/pkg | cut -f1))"
