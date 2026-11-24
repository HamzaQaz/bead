#!/usr/bin/env python3
"""Makes modules/welcome/script.js, the welcome title's pen path, from EMS
Allure: a single-line script font drawn as pen strokes (Sheldon B. Michaels,
from Allura by Rob Leuschke; SIL Open Font License; part of Evil Mad
Scientist's Hershey Text, github.com/evil-mad/EggBot):

    python3 tools/handwriting.py EMSAllure.svg modules/welcome/script.js

Each letter is already one pen stroke (the d's ascender a loop), so the word
needs no tracing, only putting in writing order and joining: the a and d are
stored back to front, the b's bowl is turned to end in a little tie, and each
join runs from one letter's exit to the next one's start. A bowl starts at its
top right, so the join into it rides just under the bowl's top, and the pen
comes back over it to fill it in, never across the middle. Smoothed through
the font's points, then evenly spaced, so the pen moves at an even pace.
"""
import math, re, sys

def load(path):
    s, g = open(path).read(), {}
    for m in re.finditer(r'<glyph\b([^>]*)/?>', s):
        a = m.group(1)
        u, d, w = (re.search(rf'{k}="([^"]*)"', a) for k in ('unicode', r'\bd', 'horiz-adv-x'))
        if u and d:
            pts = [(float(x), -float(y)) for x, y in re.findall(r'(-?[\d.]+)\s+(-?[\d.]+)', d.group(1))]
            g[u.group(1)] = (pts, float(w.group(1)))
    return g

def hermite(p0, t0, p1, t1, n=12):
    out = []
    for k in range(1, n):
        s = k / n
        h = (2*s**3 - 3*s**2 + 1, -2*s**3 + 3*s**2, s**3 - 2*s**2 + s, s**3 - s**2)
        out.append(tuple(h[0]*p0[i] + h[1]*p1[i] + h[2]*t0[i] + h[3]*t1[i] for i in (0, 1)))
    return out

def unit(p, q, scale=1.0):
    l = math.dist(p, q) or 1
    return ((q[0] - p[0]) / l * scale, (q[1] - p[1]) / l * scale)

def join(line, nxt, under=()):
    """From the line's end to nxt's start: a smooth curve, or (into a bowl) one
    through `under`, the points just below the bowl's top."""
    way = [line[-1], *under, nxt[0]]
    t = unit(line[-2], line[-1])
    for p, q in zip(way, way[1:]):
        last = q is way[-1]
        t1 = unit(nxt[0], nxt[1]) if last else unit(p, q)
        L = math.dist(p, q) * 1.1
        line += hermite(p, (t[0] * L, t[1] * L), q, (t1[0] * L, t1[1] * L)) + ([] if last else [q])
        t = t1
    return line + nxt

def catmull(pts, n=6):  # a smooth curve through the font's points
    out = [pts[0]]
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        for k in range(1, n + 1):
            t = k / n
            out.append(tuple(0.5 * (2*p1[j] + (-p0[j] + p2[j])*t + (2*p0[j] - 5*p1[j] + 4*p2[j] - p3[j])*t*t
                                    + (-p0[j] + 3*p1[j] - 3*p2[j] + p3[j])*t**3) for j in (0, 1)))
    return out

def resample(p, step):
    o, acc = [p[0]], 0.0
    for a, b in zip(p, p[1:]):
        L = math.dist(a, b)
        while acc + L >= step and L > 0:
            t = (step - acc) / L
            a = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            o.append(a)
            L, acc = math.dist(a, b), 0.0
        acc += L
    if math.dist(o[-1], p[-1]) > step * 0.3:
        o.append(p[-1])
    return o

STEP = 0.008  # between points, in heights
DROP = 34     # how far under a bowl's top its join runs, in font units

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    g = load(sys.argv[1])
    x, glyphs = 0.0, {}
    for c in "bead":
        glyphs[c] = [(px + x, py) for px, py in g[c][0]]
        x += g[c][1]
    b, e, a, d = glyphs['b'], glyphs['e'], glyphs['a'][::-1], glyphs['d']
    # b: loop and stem, then from the stem's foot round the bowl to its top, and a tie out of it
    b = b[:14] + [b[i] for i in (23, 22, 21, 20, 19, 18, 17, 16)] + [(215, -300), (212, -272), (240, -262), (300, -268)]
    under = lambda pts: [(px, py + DROP) for px, py in pts]
    line = join(list(b), e)
    line = join(line, a, under(a[1:5][::-1]))  # under the a's top, left to right
    line = join(line, d, under(d[1:4][::-1]))  # under the d's top
    line = catmull(line)
    ys = [p[1] for p in line]
    x0, y0 = min(p[0] for p in line), min(ys)
    h = max(ys) - y0
    pts = resample([((px - x0) / h, (py - y0) / h) for px, py in line], STEP)
    baseline = (0 - y0) / h
    width = max(p[0] for p in pts)
    dot = (width + 0.03, baseline - 0.03)  # the full stop: a bead on the baseline, past the d
    with open(sys.argv[2], "w") as f:
        f.write('.pragma library\n'
                '// "bead." as handwriting, one pen line written left to right: EMS Allure\n'
                '// (Sheldon B. Michaels, from Allura by Rob Leuschke; SIL Open Font License),\n'
                '// its letters put in writing order and joined. Points are evenly spaced, so\n'
                '// the pen moves at an even pace; x then y, in units of the word\'s height\n'
                '// (y down). Made by tools/handwriting.py. The full stop is a bead: `dot`.\n')
        f.write(f"var aspect = {dot[0] + 0.1:.4f};\nvar lengths = [{(len(pts) - 1) * STEP:.4f}];\n")
        f.write(f"var dot = [{dot[0]:.4f}, {dot[1]:.4f}];\nvar strokes = [\n")
        f.write("    [" + ", ".join(f"{px:.4f}, {py:.4f}" for px, py in pts) + "]\n];\n")

if __name__ == "__main__":
    main()
