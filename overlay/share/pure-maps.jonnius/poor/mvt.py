# -*- coding: utf-8 -*-
"""Minimal Mapbox Vector Tile (MVT 2.x) decoder, Python standard library only.

Used by LibreMaps' offline search and routing to read OpenFreeMap tiles (the
OpenMapTiles schema). Only the layers asked for are decoded; the rest are
skipped by their length.

decode(data, layers) -> {layer_name: (extent, [Feature, ...])}
Feature: (geom_type, properties dict, geometry)
  geom_type 1 point: [(x, y), ...]
  geom_type 2 line: [[(x, y), ...], ...]   (one list per line part)
  geom_type 3 polygon: [[(x, y), ...], ...] (rings)
Coordinates are tile pixels (0..extent, can go a little outside: the buffer).
"""

import struct

POINT, LINE, POLYGON = 1, 2, 3


def _varint(buf, i):
    result = 0
    shift = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if b < 0x80:
            return result, i
        shift += 7


def _skip(buf, i, wire):
    if wire == 0:
        while buf[i] & 0x80:
            i += 1
        return i + 1
    if wire == 1:
        return i + 8
    if wire == 2:
        n, i = _varint(buf, i)
        return i + n
    if wire == 5:
        return i + 4
    raise ValueError("bad wire type %d" % wire)


def _value(buf, i, end):
    v = None
    while i < end:
        key, i = _varint(buf, i)
        field, wire = key >> 3, key & 7
        if field == 1 and wire == 2:            # string
            n, i = _varint(buf, i)
            v = bytes(buf[i:i + n]).decode("utf-8", "replace")
            i += n
        elif field == 2 and wire == 5:          # float
            v = struct.unpack_from("<f", buf, i)[0]
            i += 4
        elif field == 3 and wire == 1:          # double
            v = struct.unpack_from("<d", buf, i)[0]
            i += 8
        elif field in (4, 5) and wire == 0:     # int64, uint64
            v, i = _varint(buf, i)
            if field == 4 and v >= 1 << 63:
                v -= 1 << 64
        elif field == 6 and wire == 0:          # sint64
            n, i = _varint(buf, i)
            v = (n >> 1) ^ -(n & 1)
        elif field == 7 and wire == 0:          # bool
            n, i = _varint(buf, i)
            v = bool(n)
        else:
            i = _skip(buf, i, wire)
    return v


def _packed(buf, i, end):
    out = []
    append = out.append
    while i < end:
        result = 0
        shift = 0
        while True:
            b = buf[i]
            i += 1
            result |= (b & 0x7F) << shift
            if b < 0x80:
                break
            shift += 7
        append(result)
    return out


def _geometry(cmds, gtype):
    parts = []
    cur = None
    x = y = 0
    i = 0
    n = len(cmds)
    while i < n:
        c = cmds[i]
        i += 1
        op, count = c & 7, c >> 3
        if op == 1 or op == 2:                  # MoveTo, LineTo
            if op == 1:
                cur = []
                parts.append(cur)
            for _ in range(count):
                dx, dy = cmds[i], cmds[i + 1]
                i += 2
                x += (dx >> 1) ^ -(dx & 1)
                y += (dy >> 1) ^ -(dy & 1)
                cur.append((x, y))
        elif op == 7:                           # ClosePath
            if cur:
                cur.append(cur[0])
    if gtype == POINT:
        return [p for part in parts for p in part]
    return parts


def _layer(buf, i, end, want_props):
    name = None
    extent = 4096
    keys, values, raw = [], [], []
    while i < end:
        key, i = _varint(buf, i)
        field, wire = key >> 3, key & 7
        if field == 1 and wire == 2:
            n, i = _varint(buf, i)
            name = bytes(buf[i:i + n]).decode("utf-8")
            i += n
        elif field == 2 and wire == 2:          # feature, decoded once keys/values are known
            n, i = _varint(buf, i)
            raw.append((i, i + n))
            i += n
        elif field == 3 and wire == 2:
            n, i = _varint(buf, i)
            keys.append(bytes(buf[i:i + n]).decode("utf-8"))
            i += n
        elif field == 4 and wire == 2:
            n, i = _varint(buf, i)
            values.append(_value(buf, i, i + n))
            i += n
        elif field == 5 and wire == 0:
            extent, i = _varint(buf, i)
        else:
            i = _skip(buf, i, wire)
    feats = []
    for a, b in raw:
        gtype = 0
        tags = geom = None
        j = a
        while j < b:
            key, j = _varint(buf, j)
            field, wire = key >> 3, key & 7
            if field == 2 and wire == 2:
                n, j = _varint(buf, j)
                tags = (j, j + n)
                j += n
            elif field == 3 and wire == 0:
                gtype, j = _varint(buf, j)
            elif field == 4 and wire == 2:
                n, j = _varint(buf, j)
                geom = (j, j + n)
                j += n
            else:
                j = _skip(buf, j, wire)
        props = {}
        if tags:
            t = _packed(buf, tags[0], tags[1])
            for k in range(0, len(t) - 1, 2):
                kname = keys[t[k]]
                if want_props is None or kname in want_props:
                    props[kname] = values[t[k + 1]]
        g = _geometry(_packed(buf, geom[0], geom[1]), gtype) if geom else []
        feats.append((gtype, props, g))
    return name, extent, feats


def decode(data, layers, props=None):
    """Decode the named layers of an (uncompressed) tile. `props` optionally
    maps a layer name to the set of property names to keep."""
    buf = memoryview(data)
    out = {}
    i, end = 0, len(buf)
    while i < end:
        key, i = _varint(buf, i)
        field, wire = key >> 3, key & 7
        if field == 3 and wire == 2:
            n, i = _varint(buf, i)
            # peek at the layer name (field 1 comes first in practice, but check)
            j, lend, lname = i, i + n, None
            while j < lend:
                k2, j = _varint(buf, j)
                if k2 >> 3 == 1 and k2 & 7 == 2:
                    m, j = _varint(buf, j)
                    lname = bytes(buf[j:j + m]).decode("utf-8")
                    break
                j = _skip(buf, j, k2 & 7)
            if lname in layers:
                name, extent, feats = _layer(buf, i, lend, (props or {}).get(lname))
                out[name] = (extent, feats)
            i = lend
        else:
            i = _skip(buf, i, wire)
    return out
