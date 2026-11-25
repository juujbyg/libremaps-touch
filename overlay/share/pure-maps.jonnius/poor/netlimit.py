# -*- coding: utf-8 -*-
# LibreMaps: size caps for everything read from the network, so a broken or hostile server
# can't fill the phone's memory. The caps are far above what the real services send.
# GPL-3.0-or-later, like Pure Maps.

"""Size caps for network replies."""

REPLY = 64 << 20        # routes, search and place replies; a long Valhalla route is a few MB
TILE = 16 << 20         # one offline tile, font range, sprite or TileJSON
FEED = 16 << 20         # the DGT incident feed, compressed (about 0.25 MB in 2026)
FEED_XML = 64 << 20     # the same feed once decompressed (DGT: 6.5 MB in 2026)
JSON_DENSITY = 16       # bytes per JSON object or list, at least (real replies: 44 or more)


class TooLarge(ValueError):
    """The server sent more than the cap."""


def read_capped(response, limit):
    """Read a whole reply, refusing one longer than limit bytes."""
    chunks, total = [], 0
    while True:
        chunk = response.read(min(1 << 16, limit + 1 - total))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
        if total > limit:
            raise TooLarge("the server sent more than %s" % _size(limit))


def json_loads(data):
    """json.loads for a capped reply, refusing one made mostly of tiny objects or lists:
    those cost Python 20 to 70 times their size in memory (15 MB of "{}," took 750 MB)."""
    if data.count(b"[") + data.count(b"{") > len(data) // JSON_DENSITY + 64:
        raise TooLarge("the reply is made of too many tiny objects")
    import json
    return json.loads(data.decode("utf-8"))


class CappedReader:
    """A file-like wrapper that refuses to give out more than limit bytes (for a stream being
    decompressed while it is parsed, where the compressed size says nothing)."""

    def __init__(self, raw, limit):
        self.raw, self.left = raw, limit

    def read(self, size=-1):
        if size is None or size < 0 or size > self.left + 1:
            size = self.left + 1
        data = self.raw.read(size)
        self.left -= len(data)
        if self.left < 0:
            raise TooLarge("the reply unpacks to more than the cap")
        return data


def _size(n):
    return "%d MB" % (n >> 20) if n >= 1 << 20 else "%d bytes" % n
