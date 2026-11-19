# -*- coding: utf-8 -*-
"""LibreMaps offline routes: A* over the road graph in roads.sqlite (built by
poor.offline_index from the saved map tiles). Used when the online router
can't be reached. Standard library only.

The tiles carry road class, one-way, ramps, steps, bridges and names, but no
speed limits, turn restrictions or roundabouts, so times are estimates from
the road class and turns are worked out from the road geometry.
"""

import array
import heapq
import math
import os
import sqlite3

from poor import offline_index as oi

E = oi.E

# km/h by road class
CAR_KMH = {1: 90, 2: 70, 3: 55, 4: 48, 5: 40, 6: 25, 7: 15, 8: 12}
# seconds lost at each junction (lights, give way, slowing for turns)
CAR_JUNCTION_S = {1: 0.0, 2: 1.0, 3: 6.0, 4: 6.0, 5: 5.0, 6: 4.0, 7: 4.0, 8: 4.0}
RAMP_KMH = 55
BIKE_KMH = 16
FOOT_KMH = 5
MAX_KMH = {"car": 105, "bicycle": 20, "foot": 5}
MAX_NODES = 600000          # give up after this many junctions
LOCAL_M = 3000              # cars use minor roads only this close to either end
SNAP_M = 1500               # how far a point may be from a road


class NoRoute(Exception):
    pass


def mode_of(costing):
    if costing in ("bicycle",):
        return "bicycle"
    if costing in ("pedestrian", "foot"):
        return "foot"
    return "car"


def edge_cost(mode, cls, flags, meters, forward):
    """Seconds to drive, ride or walk an edge in one direction, or None."""
    if flags & oi.F_NOACCESS:
        return None
    if mode == "car":
        if cls not in CAR_KMH:
            return None
        if (forward and flags & oi.F_BACK) or (not forward and flags & oi.F_FWD):
            return None
        kmh = RAMP_KMH if flags & oi.F_RAMP else CAR_KMH[cls]
        return meters / (kmh / 3.6) + (1.0 if flags & oi.F_RAMP else CAR_JUNCTION_S[cls])
    if mode == "bicycle":
        if cls == 1 or flags & oi.F_NOBIKE:
            return None
        if cls != 9 and ((forward and flags & oi.F_BACK) or (not forward and flags & oi.F_FWD)):
            return None
        if flags & oi.F_STEPS:
            return meters / (2 / 3.6)
        factor = {2: 2.0, 3: 1.4, 4: 1.2, 8: 1.3}.get(cls, 1.0)
        if cls == 9:
            factor = 0.9 if flags & oi.F_CYCLEWAY else 1.5 if flags & oi.F_FOOTWAY else 1.1
        return meters / (BIKE_KMH / 3.6) * factor
    # foot
    if cls == 1 or flags & oi.F_NOFOOT:
        return None
    if flags & oi.F_STEPS:
        return meters / (3 / 3.6)
    factor = {2: 1.8, 3: 1.2}.get(cls, 1.0)
    return meters / (FOOT_KMH / 3.6) * factor


class Graph:

    def __init__(self, path):
        if not os.path.exists(path):
            raise NoRoute("no offline roads")
        self.db = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
        self.nodes = {}

    def close(self):
        self.db.close()

    def node(self, nid):
        p = self.nodes.get(nid)
        if p is None:
            p = self.db.execute("SELECT x, y FROM nodes WHERE id=?", (nid,)).fetchone()
            self.nodes[nid] = p
        return p

    def neighbours(self, nid):
        return self.db.execute(
            "SELECT e.id, e.b, e.cls, e.flags, e.len, n.x, n.y, 1 FROM edges e "
            "JOIN nodes n ON n.id = e.b WHERE e.a = ? UNION ALL "
            "SELECT e.id, e.a, e.cls, e.flags, e.len, n.x, n.y, 0 FROM edges e "
            "JOIN nodes n ON n.id = e.a WHERE e.b = ?", (nid, nid)).fetchall()

    def edge(self, eid):
        return self.db.execute("SELECT id, a, b, cls, flags, len, name, geom FROM edges "
                               "WHERE id=?", (eid,)).fetchone()

    def points(self, edge):
        """An edge's points in world units, from a to b."""
        rel = array.array("h")
        rel.frombytes(edge[7])
        ax, ay = self.node(edge[1])
        ox = int(round((ax - rel[0]) / E)) * E
        oy = int(round((ay - rel[1]) / E)) * E
        pts = [(ox + rel[i], oy + rel[i + 1]) for i in range(0, len(rel), 2)]
        # the ends are the nodes (they may sit a few units off on tile edges)
        pts[0] = (ax, ay)
        pts[-1] = tuple(self.node(edge[2]))
        return pts

    def name(self, nid):
        if not nid:
            return ("", "")
        row = self.db.execute("SELECT name, ref FROM names WHERE id=?", (nid,)).fetchone()
        return row or ("", "")

    def snap(self, gx, gy, mode, mpu, outward=True):
        """The closest road open to `mode`: (edge, segment index, t, point,
        metres from a, edge length in metres)."""
        cx, cy = int(gx) >> oi.CELL_BITS, int(gy) >> oi.CELL_BITS
        reach = int(SNAP_M / mpu / (1 << oi.CELL_BITS)) + 1
        found = {}          # edge id -> (squared distance, edge, points, segment, t)
        for r in range(0, reach + 1):
            cells = [oi.cell_id(x, y) for x in range(cx - r, cx + r + 1)
                     for y in range(cy - r, cy + r + 1)
                     if max(abs(x - cx), abs(y - cy)) == r]
            ids = set()
            for i in range(0, len(cells), 200):
                part = cells[i:i + 200]
                ids.update(row[0] for row in self.db.execute(
                    "SELECT edge FROM edge_cells WHERE cell IN (%s)" % ",".join("?" * len(part)),
                    part))
            for eid in ids - set(found):
                e = self.edge(eid)
                if edge_cost(mode, e[3], e[4], 1, True) is None and                         edge_cost(mode, e[3], e[4], 1, False) is None:
                    continue
                pts = self.points(e)
                best = None
                for i in range(len(pts) - 1):
                    d2, t = oi._project((gx, gy), pts[i], pts[i + 1])
                    if best is None or d2 < best[0]:
                        best = (d2, e, pts, i, t)
                found[eid] = best
            # the closest road that joins the wider network (not a stair or
            # path fragment the tiles left unconnected)
            ring = (r * (1 << oi.CELL_BITS)) ** 2
            for d2, e, pts, i, t in sorted(found.values(), key=lambda v: v[0]):
                if d2 > ring and r < reach:
                    break       # something in the next ring may be closer
                if d2 * mpu * mpu > SNAP_M * SNAP_M:
                    break
                if not self.connected(e, mode, outward):
                    continue
                a, b = pts[i], pts[i + 1]
                p = (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))
                along = sum(_dist(pts[k], pts[k + 1]) for k in range(i)) + _dist(a, p)
                total = sum(_dist(pts[k], pts[k + 1]) for k in range(len(pts) - 1)) or 1
                return dict(edge=e, pts=pts, i=i, p=p, frac=along / total, meters=e[5] / 10.0)
        raise NoRoute("no road near")

    def connected(self, edge, mode, outward, enough=150):
        """True if, along one-way rules, the edge leads out to (outward) or
        can be reached from (not outward) at least `enough` junctions."""
        seeds = []
        if edge_cost(mode, edge[3], edge[4], 1, True) is not None:
            seeds.append(edge[2] if outward else edge[1])
        if edge_cost(mode, edge[3], edge[4], 1, False) is not None:
            seeds.append(edge[1] if outward else edge[2])
        seen = set(seeds)
        todo = list(seeds)
        while todo:
            n = todo.pop()
            for eid, m, cls, flags, dm, x, y, fwd in self.neighbours(n):
                if m in seen:
                    continue
                if edge_cost(mode, cls, flags, 1, bool(fwd) == outward) is None:
                    continue
                seen.add(m)
                if len(seen) >= enough:
                    return True
                todo.append(m)
        return False


def _dist(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])


def _part(snap, forward, to_point):
    """Points of the snapped edge between the snapped point and one end.
    forward/to_point: (True, False) point->b, (False, False) point->a,
    (True, True) a->point, (False, True) b->point."""
    pts, i, p = snap["pts"], snap["i"], snap["p"]
    if not to_point:
        return [p] + pts[i + 1:] if forward else [p] + pts[i::-1]
    return pts[:i + 1] + [p] if forward else pts[:i:-1] + [p]


def search(g, start, end, mode, mpu, local_only=True):
    """A* from snap `start` to snap `end`. Returns a list of steps
    (edge row or None, points, seconds)."""
    S, T = -1, -2
    vmax = MAX_KMH[mode] / 3.6
    tx, ty = end["p"]
    sx, sy = start["p"]

    def h(x, y):
        return math.hypot(tx - x, ty - y) * mpu / vmax

    e0, e1 = start["edge"], end["edge"]
    best = {S: 0.0}
    parent = {}
    heap = []
    # leaving the start along its road
    for forward in (True, False):
        c = edge_cost(mode, e0[3], e0[4], start["meters"], forward)
        if c is None:
            continue
        frac = (1 - start["frac"]) if forward else start["frac"]
        n = e0[2] if forward else e0[1]
        cost = c * frac
        if cost < best.get(n, 1e18):
            best[n] = cost
            parent[n] = (S, e0, _part(start, forward, False), cost)
            x, y = g.node(n)
            heapq.heappush(heap, (cost + h(x, y), cost, n))
    # start and end on the same road
    if e0[0] == e1[0]:
        forward = end["frac"] >= start["frac"]
        c = edge_cost(mode, e0[3], e0[4], start["meters"], forward)
        if c is not None:
            cost = c * abs(end["frac"] - start["frac"])
            pts, i, j = start["pts"], start["i"], end["i"]
            if forward:
                part = [start["p"]] + pts[i + 1:j + 1] + [end["p"]]
            else:
                part = [start["p"]] + pts[i:j:-1] + [end["p"]]
            best[T] = cost
            parent[T] = (S, e0, part, cost)
            heapq.heappush(heap, (cost, cost, T))
    # arriving: from either end of the end road
    arrive = {}
    for forward in (True, False):
        c = edge_cost(mode, e1[3], e1[4], end["meters"], forward)
        if c is None:
            continue
        frac = end["frac"] if forward else 1 - end["frac"]
        arrive[e1[1] if forward else e1[2]] = (c * frac, _part(end, forward, True))

    local2 = (LOCAL_M / mpu) ** 2
    done = set()
    while heap:
        f, cost, n = heapq.heappop(heap)
        if n == T:
            break
        if n in done or cost > best.get(n, 1e18):
            continue
        done.add(n)
        if len(done) > MAX_NODES:
            raise NoRoute("too far")
        if n in arrive:
            c, part = arrive[n]
            if cost + c < best.get(T, 1e18):
                best[T] = cost + c
                parent[T] = (n, e1, part, c)
                heapq.heappush(heap, (cost + c, cost + c, T))
        for eid, m, cls, flags, dm, x, y, fwd in g.neighbours(n):
            if m in done:
                continue
            if local_only and mode == "car" and cls >= 6:
                if (x - sx) ** 2 + (y - sy) ** 2 > local2 and (x - tx) ** 2 + (y - ty) ** 2 > local2:
                    continue
            c = edge_cost(mode, cls, flags, dm / 10.0, bool(fwd))
            if c is None:
                continue
            nc = cost + c
            if nc < best.get(m, 1e18):
                best[m] = nc
                parent[m] = (n, eid, bool(fwd), c)
                g.nodes[m] = (x, y)
                heapq.heappush(heap, (nc + h(x, y), nc, m))
    if T not in parent:
        raise NoRoute("no route")
    steps = []
    n = T
    while n != S:
        prev, e, how, c = parent[n]
        if isinstance(e, tuple):
            steps.append((e, how, c))
        else:
            row = g.edge(e)
            pts = g.points(row)
            steps.append((row, pts if how else pts[::-1], c))
        n = prev
    steps.reverse()
    return steps


# ------------------------------------------------------------------ directions

def _bearing(a, b):
    # world units: x east, y south
    return math.degrees(math.atan2(b[0] - a[0], a[1] - b[1])) % 360


def _end_bearing(pts, mpu, back=True, span=20.0):
    """Direction of travel near the end (back=True) or the start of a line."""
    seq = pts[::-1] if back else pts
    first = seq[0]
    acc = 0.0
    q = seq[0]
    for p in seq[1:]:
        acc += _dist(q, p) * mpu
        q = p
        if acc >= span:
            break
    if q == first:
        return None
    return _bearing(q, first) if back else _bearing(first, q)


def _turn(angle):
    """Icon and verb for a change of direction (degrees, + to the right)."""
    a = abs(angle)
    side = "right" if angle > 0 else "left"
    if a < 25:
        return "continue", None
    if a < 60:
        return "turn-slight-" + side, "slight-" + side
    if a < 135:
        return "turn-" + side, side
    if a < 165:
        return "turn-sharp-" + side, "sharp-" + side
    return "uturn", "uturn"


def directions(g, steps, mpu, tr):
    """Group the steps into named stretches and describe the turns between."""
    # stretches: [name, ref, cls, flags, points, seconds, metres]
    stretches = []
    for row, pts, sec in steps:
        name, ref = g.name(row[6])
        meters = sum(_dist(pts[k], pts[k + 1]) for k in range(len(pts) - 1)) * mpu
        if stretches:
            last = stretches[-1]
            same = (name or ref) and (name, ref) == (last[0], last[1])
            if not same and not (name or ref) and not (last[0] or last[1]):
                b_in = _end_bearing(last[4], mpu, True)
                b_out = _end_bearing(pts, mpu, False)
                same = b_in is None or b_out is None or \
                    abs((b_out - b_in + 180) % 360 - 180) < 50  # unnamed paths: gentle bends need no word
            if same and bool(row[4] & oi.F_RAMP) == bool(last[3] & oi.F_RAMP):
                last[4] = last[4] + pts[1:]
                last[5] += sec
                last[6] += meters
                continue
        stretches.append([name, ref, row[3], row[4], list(pts), sec, meters])

    # bits shorter than 12 m (a kink at a junction, a crossing) join the next one
    k = 0
    while k < len(stretches) - 1:
        if stretches[k][6] < 12 and len(stretches) > 2:
            nxt = stretches[k + 1]
            nxt[4] = stretches[k][4] + nxt[4][1:]
            nxt[5] += stretches[k][5]
            nxt[6] += stretches[k][6]
            del stretches[k]
        else:
            k += 1

    def label(s):
        if s[0] and s[1] and s[1] not in s[0]:
            return "%s (%s)" % (s[0], s[1])
        return s[0] or s[1]

    verbs = {"left": tr("Turn left"), "right": tr("Turn right"),
             "slight-left": tr("Bear left"), "slight-right": tr("Bear right"),
             "sharp-left": tr("Turn sharp left"), "sharp-right": tr("Turn sharp right"),
             "uturn": tr("Make a U-turn")}

    def say(kind, street):
        if kind == "depart":
            return tr("Head out on %s") % street if street else tr("Head out")
        if kind in ("exit-left", "exit-right"):
            text = tr("Take the exit on the right") if kind == "exit-right" else tr("Take the exit on the left")
            return tr("%s towards %s") % (text, street) if street else text
        if kind == "merge":
            return tr("Merge onto %s") % street if street else tr("Merge")
        return tr("%s onto %s") % (verbs[kind], street) if street else verbs[kind]

    maneuvers = []
    for k, s in enumerate(stretches):
        street = label(s)
        if k == 0:
            icon, kind = "depart", "depart"
        else:
            prev = stretches[k - 1]
            b_in = _end_bearing(prev[4], mpu, True)
            b_out = _end_bearing(s[4], mpu, False)
            angle = 0 if b_in is None or b_out is None else (b_out - b_in + 180) % 360 - 180
            icon, kind = _turn(angle)
            side = "right" if angle > 0 else "left"
            if s[3] & oi.F_RAMP and not prev[3] & oi.F_RAMP:
                icon, kind = "off-ramp-slight-" + side, "exit-" + side
            elif prev[3] & oi.F_RAMP and not s[3] & oi.F_RAMP and s[2] <= 2:
                icon, kind = "merge-slight-" + ("left" if angle < 0 else "right"), "merge"
            elif kind is None:
                # straight on: the road may change its name, but there's
                # nothing to do; the stretch joins the previous instruction,
                # which names the street followed longest
                last = maneuvers[-1]
                last["pts"] = last["pts"] + s[4][1:]
                last["duration"] += s[5]
                last["length"] += s[6]
                if street and s[6] > last["_longest"] and last["_kind"] not in ("exit-left", "exit-right"):
                    last["_longest"] = s[6]
                    last["street"] = [street]
                    last["narrative"] = say(last["_kind"], street)
                continue
        maneuvers.append(dict(pts=s[4], icon=icon, narrative=say(kind, street),
                              street=[street] if street else None, duration=s[5], length=s[6],
                              _kind=kind, _longest=s[6] if street else 0.0))
    for m in maneuvers:
        del m["_kind"], m["_longest"]
    return maneuvers


# ------------------------------------------------------------------ entry point

def covers(lon, lat):
    """True if (lon, lat) is inside a saved area with roads indexed."""
    from poor import offline
    if not os.path.exists(oi.roads_path()):
        return False
    for r in offline.done_regions():
        w, s, e, n = r["bbox"]
        if w <= lon <= e and s <= lat <= n:
            return True
    return False


def route(points, costing="auto", path=None, tr=lambda s: s):
    """Route through `points` [(lon, lat), ...]. Returns a route dict in the
    shape Pure Maps' routers return, or raises NoRoute."""
    mode = mode_of(costing)
    g = Graph(path or oi.roads_path())
    try:
        X, Y, man, ind = [], [], [], [0]
        total_s = total_m = 0.0
        ws = [oi.world(lon, lat) for lon, lat in points]
        mpu = oi.meters_per_unit(sum(w[1] for w in ws) / len(ws))
        for leg in range(len(ws) - 1):
            a = g.snap(ws[leg][0], ws[leg][1], mode, mpu)
            b = g.snap(ws[leg + 1][0], ws[leg + 1][1], mode, mpu, outward=False)
            try:
                steps = search(g, a, b, mode, mpu, local_only=True)
            except NoRoute:
                if mode != "car":
                    raise
                steps = search(g, a, b, mode, mpu, local_only=False)
            dirs = directions(g, steps, mpu, tr)
            for k, m in enumerate(dirs):
                pts = m.pop("pts")
                if X and k == 0:
                    pts = pts[1:] if pts else pts
                lonlats = [oi.lonlat(p[0], p[1]) for p in pts]
                first = len(X)
                X.extend(p[0] for p in lonlats)
                Y.extend(p[1] for p in lonlats)
                if lonlats:
                    m["x"], m["y"] = X[first], Y[first]
                    man.append(m)
                total_s += m["duration"]
                total_m += m["length"]
            ind.append(len(X) - 1)
        if X:
            man.append(dict(x=X[-1], y=Y[-1], icon="arrive",
                            narrative=tr("You have arrived at your destination"),
                            street=None, duration=0.0, length=0.0))
        return dict(x=X, y=Y, maneuvers=man, location_indexes=ind,
                    mode={"car": "car", "bicycle": "bicycle", "foot": "foot"}[mode],
                    optimized=False, offline=True, seconds=total_s, meters=total_m)
    finally:
        g.close()
