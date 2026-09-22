#!/usr/bin/env python3
"""Walks every floor in src/core/levels.gd and fails loudly if one is broken.

It flies a simulated player around each floor with the same gravity and jump
speed as src/player/player.gd, but a slower run speed than the real thing, so
anything it accepts has some slack in it. For every floor it checks that:

  - the beacon can be reached from the start,
  - the stairway can be reached from the beacon,
  - every flask of oil can be reached,
  - there is nowhere you can stand that you cannot get back out of.

Run it from the project folder:  python3 tools/check_levels.py
Standard library only. The last check, the one that looks for places to get
stuck, is slow on floors this size. Add --quick to skip it.
"""
import math
import os
import re
import sys
from collections import deque

T = 16
GRAV = 980.0
JUMP_V = -330.0
MAX_FALL = 420.0
CHECK_RUN = 104.0          # the game runs at 120
PW, PH = 10.0, 16.0        # the player's collider

SOLID = set("#=")          # cracked stone holds long enough to land on
ONEWAY = set("-")
HAZARD = set("^v")


class Floor:
    def __init__(self, name, rows):
        self.name = name
        self.raw = [list(r.replace(".", " ")) for r in rows]
        self.h = len(self.raw)
        self.w = len(self.raw[0])
        self.g = self._effective()

    def _effective(self):
        """What the pretend player walks on. A rail or a lift counts as a
        ledge along its whole length, since the slab passes every point of it
        and you can always wait for it. Shadows, oil, leaks and loose stones
        are air."""
        g = [row[:] for row in self.raw]
        for y in range(self.h):
            for x in range(self.w):
                c = self.raw[y][x]
                if c in "m~":
                    g[y][x] = "-"
                elif c in "Fkbwlhfd":
                    g[y][x] = " "
        for y in range(self.h):
            for x in range(self.w):
                if self.raw[y][x] in "n:":
                    for dx in range(3):
                        if x + dx < self.w and self.raw[y][x + dx] in " n:":
                            g[y][x + dx] = "-"
        return g

    def at(self, x, y):
        if x < 0 or x >= self.w or y < 0:
            return "#"
        if y >= self.h:
            return " "
        return self.g[y][x]

    def find(self, ch):
        return [(x, y) for y in range(self.h) for x in range(self.w) if self.raw[y][x] == ch]


def box_hits(fl, x0, y0, x1, y1, kinds):
    for ty in range(int(math.floor(y0 / T)), int(math.floor((y1 - 0.01) / T)) + 1):
        for tx in range(int(math.floor(x0 / T)), int(math.floor((x1 - 0.01) / T)) + 1):
            if fl.at(tx, ty) in kinds:
                return True
    return False


def hazard_box(fl, x0, y0, x1, y1):
    # spikes only bite in the pointy half of their tile, same as the game
    for ty in range(int(math.floor(y0 / T)), int(math.floor((y1 - 0.01) / T)) + 1):
        for tx in range(int(math.floor(x0 / T)), int(math.floor((x1 - 0.01) / T)) + 1):
            c = fl.at(tx, ty)
            if c == "^" and y1 > ty * T + 8 and x1 > tx * T + 2 and x0 < tx * T + 14:
                return True
            if c == "v" and y0 < ty * T + 8 and x1 > tx * T + 2 and x0 < tx * T + 14:
                return True
    return False


def standable(fl, c, r):
    return fl.at(c, r) not in SOLID and fl.at(c, r) not in HAZARD and \
        (fl.at(c, r + 1) in SOLID or fl.at(c, r + 1) in ONEWAY)


def simulate(fl, c, r, vx, vy):
    """Fly from standing tile (c, r). Returns the tile you land on, or None."""
    x = c * T + T / 2.0
    feet = (r + 1) * T
    dt = 1.0 / 60.0
    for _ in range(60 * 6):
        vy = min(MAX_FALL, vy + GRAV * dt)
        nx = x + vx * dt
        if box_hits(fl, nx - PW / 2, feet - PH, nx + PW / 2, feet, SOLID):
            vx = 0.0
        else:
            x = nx
        nf = feet + vy * dt
        if vy < 0:
            if box_hits(fl, x - PW / 2, nf - PH, x + PW / 2, nf, SOLID):
                vy = 0.0
                nf = feet
        else:
            k = int(math.floor(nf / T))
            y_top = k * T
            if feet <= y_top + 0.001 and nf >= y_top:
                cols = range(int(math.floor((x - PW / 2) / T)), int(math.floor((x + PW / 2 - 0.01) / T)) + 1)
                if any(fl.at(tx, k) in SOLID or fl.at(tx, k) in ONEWAY for tx in cols):
                    land_row = k - 1
                    if hazard_box(fl, x - PW / 2, y_top - PH, x + PW / 2, y_top):
                        return None
                    cc = int(math.floor(x / T))
                    if standable(fl, cc, land_row):
                        return (cc, land_row)
                    for alt in cols:
                        if standable(fl, alt, land_row):
                            return (alt, land_row)
                    return None
            if box_hits(fl, x - PW / 2, nf - PH, x + PW / 2, nf, SOLID):
                vx = 0.0
        feet = nf
        if hazard_box(fl, x - PW / 2, feet - PH, x + PW / 2, feet):
            return None
        if feet > (fl.h + 2) * T:
            return None
    return None


def neighbours(fl, c, r):
    out = []
    for d in (-1, 1):
        if fl.at(c + d, r) not in SOLID and fl.at(c + d, r) not in HAZARD:
            if standable(fl, c + d, r):
                out.append(((c + d, r), 1.0))
            else:
                for vx in (CHECK_RUN * d, CHECK_RUN * d * 0.5):
                    land = simulate(fl, c, r, vx, 0.0)
                    if land:
                        out.append((land, abs(land[0] - c) + abs(land[1] - r) * 0.5))
    for k in (-1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0):
        land = simulate(fl, c, r, CHECK_RUN * k, JUMP_V)
        if land and land != (c, r):
            out.append((land, abs(land[0] - c) + 1.5))
    return out


def reach(fl, start, cache):
    if start in cache:
        return cache[start]
    dist = {start: 0.0}
    q = deque([start])
    while q:
        n = q.popleft()
        for m, cost in neighbours(fl, *n):
            nd = dist[n] + cost
            if m not in dist or nd < dist[m] - 1e-6:
                dist[m] = nd
                q.append(m)
    cache[start] = dist
    return dist


def load_floors(path):
    src = open(path, encoding="utf-8").read()
    floors = []
    for block in re.finditer(r'"name":\s*"([^"]+)".*?"rows":\s*\[(.*?)\]', src, re.S):
        rows = re.findall(r'"([^"]*)"', block.group(2))
        floors.append(Floor(block.group(1), rows))
    return floors


def check(fl, deep=True):
    problems = []
    widths = {len(r) for r in fl.raw}
    if len(widths) != 1:
        problems.append("rows are not all the same width: %s" % sorted(widths))
        return problems
    p, b, s = fl.find("P"), fl.find("B"), fl.find("S")
    if len(p) != 1 or len(b) != 1 or len(s) != 1:
        problems.append("needs exactly one P, B and S (found %d, %d, %d)" % (len(p), len(b), len(s)))
        return problems
    cache = {}
    d = reach(fl, p[0], cache)
    bx, by = b[0]
    sx, sy = s[0]
    near_b = lambda dd: [n for n in dd if n[1] == by and bx - 1 <= n[0] <= bx + 2]
    near_s = lambda dd: [n for n in dd if n[1] == sy and sx - 1 <= n[0] <= sx + 2]
    nb = near_b(d)
    if not nb:
        problems.append("the beacon cannot be reached from the start")
        return problems
    d2 = reach(fl, min(nb, key=lambda n: d[n]), cache)
    if not near_s(d2):
        problems.append("the stairway cannot be reached from the beacon")
    for f in fl.find("f"):
        if f not in d and f not in d2:
            problems.append("the oil at %s is out of reach" % (f,))
    if deep:
        for n in list(d) + list(d2):
            dd = reach(fl, n, cache)
            if not near_b(dd) and not near_s(dd):
                problems.append("you can get stuck at %s" % (n,))
                break
    return problems


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "src", "core", "levels.gd")
    deep = "--quick" not in sys.argv
    floors = load_floors(path)
    bad = 0
    for i, fl in enumerate(floors, 1):
        problems = check(fl, deep)
        if problems:
            bad += 1
            print("depth %d, %s:" % (i, fl.name))
            for pr in problems:
                print("   " + pr)
        else:
            print("depth %d, %s: fine" % (i, fl.name))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
