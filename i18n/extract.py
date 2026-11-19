"""List the translatable strings LibreMaps adds on top of Pure Maps.

Finds app.tr("..."), qsTr("...") and qsTranslate("", "...") calls in the
overlay's QML, joining literals split with + across lines, and keeps those
that Pure Maps' own catalogues don't already cover (directly, or with
"Pure Maps" renamed to "LibreMaps"). Writes i18n/strings.json.
"""
import glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import qm  # noqa: E402

LIT = r'"(?:[^"\\]|\\.)*"'
CALL = re.compile(r'(?:\bapp\.tr|\bqsTr|\bqsTranslate\(\s*""\s*,)\s*\(?\s*(' + LIT + r'(?:\s*\+\s*' + LIT + r')*)\s*([,)])')


def unescape(lit):
    return json.loads(lit)   # JS string literals here are JSON-compatible


def found(root):
    out = {}
    for p in glob.glob(os.path.join(root, "**", "*.qml"), recursive=True):
        text = open(p, encoding="utf-8").read()
        for m in CALL.finditer(text):
            parts = re.findall(LIT, m.group(1))
            s = "".join(unescape(x) for x in parts)
            out.setdefault(s, set()).add(os.path.relpath(p, root))
    # Python: tr("...") in the overlay's own modules (offline directions);
    # they go to the gettext catalogue that build.py writes
    for p in glob.glob(os.path.join(root, "poor", "offline*.py")):
        text = open(p, encoding="utf-8").read()
        for m in PY_CALL.finditer(text):
            out.setdefault(unescape(m.group(1)), set()).add(os.path.relpath(p, root))
    return out


PY_CALL = re.compile(r'\btr\(\s*(' + LIT + r')\s*\)')


def known_sources():
    src = set()
    for f in glob.glob(os.path.join(ROOT, "orig/share/pure-maps.jonnius/translations/*.qm")):
        for (_, s) in qm.read(f):
            src.add(s)
            src.add(s.replace("Pure Maps", "LibreMaps"))
    return src


if __name__ == "__main__":
    have = known_sources()
    new = found(os.path.join(ROOT, "overlay/share/pure-maps.jonnius"))
    # Python strings stay even when Pure Maps' QML has them: gettext has its
    # own catalogue
    todo = sorted(s for s in new if s.strip() and (s not in have or
                                                   any(f.endswith(".py") for f in new[s])))
    json.dump(todo, open(os.path.join(HERE, "strings.json"), "w"), ensure_ascii=False, indent=1)
    print(len(todo), "strings to translate")
