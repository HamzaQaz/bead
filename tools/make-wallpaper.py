#!/usr/bin/env python3
"""bead's wallpapers: glossy ribbons of colour folding through the dark, and
one glass bead among them that bends them like a lens.

Each ribbon twists as it flows (its back face shows where it turns over), is
lit by a soft key light with a sharp sheen and a bright edge, and casts a soft
shadow on the ones behind it; one is frosted glass. The bead refracts the
picture behind it (upside down, as a glass ball does, with a little colour
fringing) and reflects what's around it. Then bloom, a vignette, a filmic
tone curve and grain.

Variants change the colours and the layout:
  bead   cyan → violet → magenta (the default)
  ember  deep red → amber
  tide   deep blue → teal → mint
  mono   graphite, for the Mono colour setting
  dusk   indigo → rose → peach, mirrored
  solo   a big bead, the ribbons passing behind it

    tools/make-wallpaper.py [variant] [out.jpg] [width] [height]
    tools/make-wallpaper.py all [dir]      every variant, 4K, as <dir>/<variant>.jpg

Only numpy and Pillow.
"""
import math
import sys

import numpy as np
from PIL import Image

F = np.float32

VARIANTS = {
    "bead": dict(ramp=[(40, 190, 240), (80, 110, 255), (150, 70, 255), (220, 60, 220), (255, 80, 150)],
                 bg=(9, 7, 18), seed=4),
    "ember": dict(ramp=[(120, 20, 40), (200, 40, 40), (240, 95, 40), (255, 150, 60), (255, 210, 130)],
                  bg=(13, 7, 6), seed=6),
    "tide": dict(ramp=[(30, 50, 170), (30, 120, 220), (20, 180, 210), (50, 220, 180), (170, 250, 220)],
                 bg=(4, 9, 14), seed=12),
    "mono": dict(ramp=[(70, 72, 80), (120, 122, 130), (170, 172, 180), (215, 216, 222), (245, 245, 248)],
                 bg=(9, 9, 10), seed=3),
    "dusk": dict(ramp=[(70, 50, 190), (150, 70, 200), (235, 95, 160), (255, 145, 120), (255, 200, 160)],
                 bg=(11, 8, 16), seed=9, mirror=True),
    "solo": dict(ramp=[(40, 190, 240), (80, 110, 255), (150, 70, 255), (220, 60, 220), (255, 80, 150)],
                 bg=(8, 7, 17), seed=9, orb=(0.64, 0.5, 0.25), ribbons=5),
}

if len(sys.argv) > 1 and sys.argv[1] == "all":
    import subprocess
    out = sys.argv[2] if len(sys.argv) > 2 else "data/wallpapers"
    for v in VARIANTS:
        subprocess.run([sys.executable, __file__, v, f"{out}/{v}.jpg"], check=True)
    sys.exit(0)

NAME = sys.argv[1] if len(sys.argv) > 1 else "bead"
V = VARIANTS[NAME]
OUT = sys.argv[2] if len(sys.argv) > 2 else f"data/wallpapers/{NAME}.jpg"
W = int(sys.argv[3]) if len(sys.argv) > 3 else 3840
H = int(sys.argv[4]) if len(sys.argv) > 4 else 2160
AR = W / H
rng = np.random.default_rng(V["seed"])


def col(c, k=1.0):
    return (np.array(c, F) / 255) ** 2.2 * k   # sRGB → linear


RAMP = np.array([col(c) for c in V["ramp"]], F)


def ramp(t):
    t = np.clip(t, 0, 1) * (len(RAMP) - 1)
    i = np.minimum(t.astype(int), len(RAMP) - 2)
    f = (t - i)[..., None]
    return RAMP[i] * (1 - f) + RAMP[i + 1] * f


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def box(a, r, axis):
    if r < 1:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(F)


def blur(a, sigma):
    """near-gaussian: three box passes each way (sigma in pixels)"""
    if sigma < 0.5:
        return a
    r = max(1, int(round((math.sqrt(4 * sigma * sigma + 1) - 1) / 2)))
    for _ in range(3):
        a = box(box(a, r, 0), r, 1)
    return a


def norm3(x, y, z):
    n = np.sqrt(x * x + y * y + z * z) + 1e-6
    return x / n, y / n, z / n


# ── coordinates: units of the screen's height, y down ──
xs = ((np.arange(W) + 0.5) / H).astype(F)
ys = ((np.arange(H) + 0.5) / H).astype(F)
u = xs / AR                       # 0..1 across
X, Y = np.meshgrid(xs, ys)

# ── the background: near black, lifted by big soft glows of the palette ──
img = np.broadcast_to(col(V["bg"]), (H, W, 3)).astype(F).copy()
for gx, gy, gs, gt, gk in ((0.25, 0.25, 0.45, 0.1, 0.10), (0.75, 0.8, 0.5, 0.9, 0.09), (0.55, 0.45, 0.3, 0.5, 0.05)):
    g = np.exp(-(((X - gx * AR) / (gs * 1.3)) ** 2 + ((Y - gy) / gs) ** 2))
    img += g[..., None] * ramp(np.array(gt)) * gk

# ── the ribbons, back to front ──
L = np.array(norm3(-0.35, 0.7, 0.62), F)      # the key light: up and to the left (y up here)
Hh = np.array(norm3(L[0], L[1], L[2] + 1), F)
N = V.get("ribbons", 7)
order = list(range(N))
rng.shuffle(order)                             # depth order differs from the stacking order
glass = order[-2]                              # one ribbon near the front is frosted glass
for k in order:
    off = k - (N - 1) / 2
    a1, f1, p1 = rng.uniform(0.015, 0.04), rng.uniform(0.6, 1.1), rng.uniform(0, 1)
    tw, tf, tp = rng.uniform(0.9, 1.8), rng.uniform(0.5, 1.0), rng.uniform(0, 1)
    wd = rng.uniform(0.028, 0.06)
    c0 = k / max(1, N - 1)
    # the bundle: tight at the upper left, fanning out to the lower right
    spread = 0.01 + 0.085 * u ** 1.25
    yc = (0.18 + 0.62 * u - 0.12 * u * u + 0.055 * np.sin(2 * np.pi * (0.85 * u + 0.15))
          + off * spread + a1 * np.sin(2 * np.pi * (f1 * u + p1)) * (0.3 + u))
    dyc = np.gradient(yc, xs)
    hw = wd * (0.55 + 0.45 * u) * (0.8 + 0.2 * np.sin(2 * np.pi * (1.3 * u + p1)))
    th = tw * np.sin(2 * np.pi * (tf * u + tp))           # the twist along it
    hwp = hw * (0.12 + 0.88 * np.abs(np.cos(th)))         # the width you see
    top, bot = int(max(0, (yc - hwp).min() * H - 3)), int(min(H, (yc + hwp).max() * H + 3))
    if bot <= top:
        continue
    yy = ys[top:bot, None]
    v = (yy - yc[None, :]) / hwp[None, :]                  # -1 top edge … 1 bottom edge
    a = np.clip((1 - np.abs(v)) * hwp[None, :] * H, 0, 1)  # anti-aliased coverage
    phi = th[None, :] - v * 0.9                            # it curls across its width too
    s = (dyc / np.sqrt(1 + dyc * dyc))[None, :]
    nx, ny, nz = norm3(s * np.sin(phi) * 0.8, np.cos(phi) * 0 + np.sin(phi), np.cos(phi))
    face = np.sign(nz)                                     # back face where it has turned over
    nx, ny, nz = nx * face, ny * face, nz * face
    dif = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    nh = np.clip(nx * Hh[0] + ny * Hh[1] + nz * Hh[2], 0, 1)
    spec = nh ** 90 * 2.2 + nh ** 12 * 0.22
    fres = (1 - nz) ** 3
    t = c0 * 0.6 + 0.45 * u[None, :]
    base = np.where((face > 0)[..., None], ramp(t), ramp(t + 0.3) * 0.5)
    c = base * (0.1 + 0.95 * dif)[..., None] + base * (fres * 0.9)[..., None] + spec[..., None] * 0.9
    c += base * (smooth(0.86, 1, np.abs(v)) * 0.5)[..., None]   # the bright cut edge
    region = img[top:bot]
    if k == glass:                                         # frosted: the picture behind, blurred and lit
        behind = blur(region, 0.025 * H)
        c = behind * 0.55 + base * 0.35 * (0.3 + dif)[..., None] + spec[..., None] * 0.9 + base * (fres * 0.9)[..., None]
        a = a * 0.92
    # its shadow on what's behind: soft, a little below
    sh = np.zeros((H, W), F)
    sh[top:bot] = a
    sh = blur(np.roll(sh, int(0.018 * H), axis=0), 0.022 * H)
    img *= (1 - 0.6 * sh)[..., None]
    region = img[top:bot]
    img[top:bot] = region * (1 - a[..., None]) + c * a[..., None]

# ── the bead: a glass ball over it all ──
ox, oy, orr = V.get("orb", (0.7, 0.3, 0.085))
cx, cy, r = ox * W, oy * H, orr * H                        # pixels
dist = np.hypot(X * H - cx, Y * H - cy) / r
img *= (1 - 0.45 * np.exp(-np.maximum(dist - 0.95, 0) ** 2 / 0.12) * (dist > 0.9))[..., None]  # a soft dark halo
x0, x1, y0, y1 = int(max(0, cx - r - 2)), int(min(W, cx + r + 3)), int(max(0, cy - r - 2)), int(min(H, cy + r + 3))
py, px = np.mgrid[y0:y1, x0:x1].astype(F) + 0.5
dx, dy = (px - cx) / r, (py - cy) / r
rr = np.sqrt(dx * dx + dy * dy)
z = np.sqrt(np.clip(1 - rr * rr, 0, 1))
soft = blur(img, 0.004 * H)
wide = blur(img, 0.03 * H)


def sample(a, sx, sy):
    sx = np.clip(sx, 0, W - 1.001); sy = np.clip(sy, 0, H - 1.001)
    i0, j0 = sx.astype(int), sy.astype(int)
    fx, fy = (sx - i0)[..., None], (sy - j0)[..., None]
    return (a[j0, i0] * (1 - fx) * (1 - fy) + a[j0, i0 + 1] * fx * (1 - fy)
            + a[j0 + 1, i0] * (1 - fx) * fy + a[j0 + 1, i0 + 1] * fx * fy)


# refraction: what's behind, upside down and magnified, each colour bent a little differently
refr = np.zeros(dx.shape + (3,), F)
for ch, disp in enumerate((0.97, 1.0, 1.03)):
    k = (1.3 - 0.6 * z) * disp
    refr[..., ch] = sample(soft, cx - dx * r * k, cy - dy * r * k)[..., ch]
tint = 0.6 + 0.4 * ramp(np.array(0.75)) / ramp(np.array(0.75)).max()
refr *= tint * 0.95
# reflection: what's around it, and a little sky
refl = sample(wide, cx + dx * r * 1.6, cy + dy * r * 1.6) * 1.4 + (smooth(0.0, 0.9, -dy) * 0.12)[..., None]
fr = (0.04 + 0.96 * (1 - z) ** 4)[..., None]
c = refr * (1 - fr) + refl * fr
# the key light's reflection: a soft rounded window, and a sharp glint in it
q = ((dx + 0.36) / 0.24) ** 2 + ((dy + 0.46) / 0.14) ** 2
c += (np.clip(1.15 - q, 0, 1) ** 1.6 * 1.3)[..., None]
c += (np.exp(-((dx + 0.3) ** 2 + (dy + 0.42) ** 2) / 0.0015) * 4)[..., None]
# light focused through it, glowing low inside; and a coloured rim on the shadow side
c += np.exp(-((dx - 0.12) ** 2 + (dy - 0.62) ** 2) / 0.05)[..., None] * ramp(np.array(0.85)) * 1.6
c += (smooth(0.8, 1.0, rr) * np.clip(dx * 0.4 + dy * 0.9, 0, 1))[..., None] * ramp(np.array(0.35)) * 2.2
a = np.clip((1 - rr) * r, 0, 1)[..., None]
img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - a) + c * a
del soft, wide

# ── post ──
bright = np.maximum(img - 0.85, 0)
img += blur(bright, 0.003 * H) * 0.5 + blur(bright, 0.012 * H) * 0.35 + blur(bright, 0.04 * H) * 0.25
del bright
img *= np.clip(1 - 0.75 * (((X / AR - 0.5) * 1.1) ** 2 + ((Y - 0.5) * 1.2) ** 2), 0, 1)[..., None]
img *= 1.2
img = (img * (2.51 * img + 0.03)) / (img * (2.43 * img + 0.59) + 0.14)   # ACES
img = np.clip(img, 0, 1) ** (1 / 2.2)
img += np.random.default_rng(11).normal(0, 0.008, (H, W, 1)).astype(F)
out = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
if V.get("mirror"):
    out = out[:, ::-1]
Image.fromarray(np.ascontiguousarray(out), "RGB").save(OUT, quality=94, subsampling=0, optimize=True)
print(OUT, W, H)
