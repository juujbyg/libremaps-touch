"""Read Qt .qm translation files (source text -> translation)."""
import struct

MAGIC = bytes([0x3C, 0xB8, 0x64, 0x18, 0xCA, 0xEF, 0x9C, 0x95,
               0xCD, 0x21, 0x1C, 0xBF, 0x60, 0xA1, 0xBD, 0xDD])


def read(path):
    data = open(path, "rb").read()
    assert data[:16] == MAGIC, "not a .qm file"
    i, messages = 16, None
    while i < len(data):
        tag, ln = data[i], struct.unpack(">I", data[i+1:i+5])[0]
        if tag == 0x69:
            messages = data[i+5:i+5+ln]
        i += 5 + ln
    out = {}
    if messages is None:
        return out
    j, cur = 0, {}
    while j < len(messages):
        t = messages[j]; j += 1
        if t == 1:                       # end of message
            if "source" in cur and "tr" in cur:
                out[(cur.get("context", ""), cur["source"])] = cur["tr"]
            cur = {}
        elif t == 3:                     # translation, UTF-16BE
            ln = struct.unpack(">I", messages[j:j+4])[0]; j += 4
            if ln != 0xFFFFFFFF:
                cur.setdefault("tr", messages[j:j+ln].decode("utf-16-be"))
                j += ln
        elif t in (6, 7, 8):             # source, context, comment (UTF-8)
            ln = struct.unpack(">I", messages[j:j+4])[0]; j += 4
            s = messages[j:j+ln].decode("utf-8", "replace"); j += ln
            cur[{6: "source", 7: "context", 8: "comment"}[t]] = s
        elif t == 5:                     # obsolete hash
            j += 4
        elif t in (2, 4):                # obsolete UTF-16 source/context
            ln = struct.unpack(">I", messages[j:j+4])[0]; j += 4 + ln
        elif t == 9:
            ln = struct.unpack(">I", messages[j:j+4])[0]; j += 4 + ln
        else:
            raise ValueError("unknown tag %d at %d" % (t, j))
    return out
