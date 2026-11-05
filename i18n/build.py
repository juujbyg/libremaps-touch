"""Build LibreMaps' translations.

For every language Pure Maps ships, combine:
  1. Pure Maps' own translations (orig/.../translations/*.qm),
  2. the same entries with "Pure Maps" renamed to "LibreMaps" (strings the
     overlay rebranded), and
  3. LibreMaps' own strings from i18n/tr/<code>.json (see i18n/strings.json),
then write
  overlay/share/pure-maps.jonnius/translations/libremaps.juujbyg-<lang>.qm
  (the binary, patched to libremaps.juujbyg, loads <name>-<locale>.qm), and
  overlay/share/pure-maps.jonnius/locale/<lang>/LC_MESSAGES/pure-maps.mo
  (Python gettext: router and guide descriptions).

usage: <python with PySide6> i18n/build.py
Needs pyside6-lrelease (the libremedia venv has it); the outputs are committed,
so building the app doesn't need PySide6.
"""
import glob, gettext, json, os, shutil, struct, subprocess, sys, tempfile
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import qm  # noqa: E402

ORIG = os.path.join(ROOT, "orig/share/pure-maps.jonnius")
OUT = os.path.join(ROOT, "overlay/share/pure-maps.jonnius")
NAME = "libremaps.juujbyg"
# Pure Maps' file suffix -> our translation file (None: Pure Maps' strings only)
OURS = {"cs": "cs", "de_DE": "de", "el": "el", "es": "es", "et": "et", "fi": "fi",
        "fr": "fr", "fur": None, "hu_HU": "hu", "it": "it", "nb": "nb", "nl": "nl",
        "nl_BE": "nl", "pl": "pl", "pt_BR": "pt_BR", "ru": "ru", "sk_SK": "sk",
        "sl_SI": "sl", "sv": "sv", "zh_CN": "zh_CN"}
LRELEASE = shutil.which("pyside6-lrelease") or os.path.join(os.path.dirname(sys.executable), "pyside6-lrelease")


def ours(code):
    if not code:
        return {}
    p = os.path.join(HERE, "tr", code + ".json")
    if not os.path.exists(p):
        print("  (no %s yet)" % os.path.relpath(p, ROOT))
        return {}
    return json.load(open(p, encoding="utf-8"))


def write_ts(path, lang, entries):
    with open(path, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n')
        f.write('<TS version="2.1" language="%s">\n<context>\n<name></name>\n' % lang)
        for src in sorted(entries):
            f.write("<message>\n<source>%s</source>\n<translation>%s</translation>\n</message>\n"
                    % (escape(src), escape(entries[src])))
        f.write("</context>\n</TS>\n")


def write_mo(path, catalog):
    """GNU .mo writer (what msgfmt produces, without hash table)."""
    keys = sorted(k for k in catalog if k)
    ids = b"".join(k.encode() + b"\0" for k in keys)
    strs = b"".join(catalog[k].encode() + b"\0" for k in keys)
    # header entry (msgid "") first, so gettext knows the charset
    header = catalog.get("", "Content-Type: text/plain; charset=UTF-8\n")
    keys = [""] + keys
    vals = [header] + [catalog[k] for k in keys[1:]]
    n = len(keys)
    o_ids, o_strs = 28, 28 + 8 * n
    start = 28 + 16 * n
    kb = [k.encode() for k in keys]
    vb = [v.encode() for v in vals]
    id_tab, pos = [], start
    for b in kb:
        id_tab.append((len(b), pos)); pos += len(b) + 1
    str_tab = []
    for b in vb:
        str_tab.append((len(b), pos)); pos += len(b) + 1
    out = struct.pack("<7I", 0x950412de, 0, n, o_ids, o_strs, 0, 0)
    out += b"".join(struct.pack("<2I", *t) for t in id_tab)
    out += b"".join(struct.pack("<2I", *t) for t in str_tab)
    out += b"".join(b + b"\0" for b in kb) + b"".join(b + b"\0" for b in vb)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(out)
    del ids, strs


def check_qm(path, samples):
    """Load the file with Qt's own QTranslator and look entries up."""
    from PySide6.QtCore import QTranslator
    t = QTranslator()
    assert t.load(path), "Qt can't load " + path
    bad = [s for s, want in samples if t.translate("", s) != want]
    return bad


def main():
    strings = json.load(open(os.path.join(HERE, "strings.json"), encoding="utf-8"))
    tdir = os.path.join(OUT, "translations")
    os.makedirs(tdir, exist_ok=True)
    for f in glob.glob(os.path.join(tdir, NAME + "-*.qm")):
        os.remove(f)
    tmp = tempfile.mkdtemp()
    for lang, code in OURS.items():
        base = {s: t for (_, s), t in qm.read(os.path.join(ORIG, "translations",
                                                           "pure-maps.jonnius-%s.qm" % lang)).items()}
        entries = dict(base)
        for s, t in base.items():
            if "Pure Maps" in s:
                entries[s.replace("Pure Maps", "LibreMaps")] = t.replace("Pure Maps", "LibreMaps")
        mine = ours(code)
        missing = [s for s in strings if s not in mine]
        entries.update({s: t for s, t in mine.items() if s in strings and t})
        ts = os.path.join(tmp, "%s.ts" % lang)
        write_ts(ts, lang, entries)
        out = os.path.join(tdir, "%s-%s.qm" % (NAME, lang))
        subprocess.run([LRELEASE, "-silent", ts, "-qm", out], check=True)
        samples = [(s, entries[s]) for s in list(mine)[:40] + list(base)[:40]]
        bad = check_qm(out, samples)
        # Python gettext: Pure Maps' catalogue plus our descriptions
        mo_in = os.path.join(ORIG, "locale", lang, "LC_MESSAGES", "pure-maps.mo")
        cat = dict(gettext.GNUTranslations(open(mo_in, "rb"))._catalog) if os.path.exists(mo_in) else {}
        for s, t in mine.items():
            if s in strings and t:
                cat[s] = t
        mo_out = os.path.join(OUT, "locale", lang, "LC_MESSAGES", "pure-maps.mo")
        write_mo(mo_out, cat)
        mo_ok = all(gettext.GNUTranslations(open(mo_out, "rb")).gettext(s) == t for s, t in list(mine.items())[:20])
        print("%-6s %4d entries, %3d of %d LibreMaps strings translated%s%s" % (
            lang, len(entries), len(strings) - len(missing), len(strings),
            "" if not bad else ", %d LOOKUPS FAILED" % len(bad), "" if mo_ok else ", .mo FAILED"))
    shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
