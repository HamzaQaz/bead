#!/usr/bin/env python3
"""bead's default wallpaper: a string of glass beads arcing through dark space.

The nearest bead is big and sharp low on the right; the string recedes up to
the left, each bead smaller and softer (depth of field). Each bead is shaded
as glass: a body that shifts hue across it, a bright rim, a sharp highlight
from a light up and to the left, and the caustic crescent glass throws on the
side away from the light. A faint thread runs through them, soft glows of
their colours sit behind, then a vignette and fine grain. The top stays dark
for the bar and the island.

Variants change the colours and the layout:
  bead   cyan → violet → magenta, the string from the upper left (the default)
  ember  deep red → amber
  tide   deep blue → teal → mint
  mono   graphite glass, for the Mono colour setting
  dusk   indigo → rose → peach, mirrored: the string from the upper right
  solo   one big bead, a few far ones behind it

    tools/make-wallpaper.py [variant] [out.jpg] [width] [height]
    tools/make-wallpaper.py all [dir]        every variant, 4K, as <dir>/<variant>.jpg
"""
import sys

import numpy as np
from PIL import Image, ImageDraw

VARIANTS = {
    "bead": dict(ramp=((40, 200, 230), (70, 110, 255), (130, 70, 255), (200, 50, 230), (255, 50, 150)), warm=(255, 150, 70), bg=(7, 6, 13)),
    "ember": dict(ramp=((110, 20, 40), (190, 35, 40), (235, 85, 40), (255, 145, 55), (255, 196, 105)), warm=(255, 232, 170), bg=(10, 5, 5)),
    "tide": dict(ramp=((25, 55, 150), (20, 115, 205), (20, 175, 205), (55, 215, 190), (140, 250, 210)), warm=(205, 255, 240), bg=(3, 8, 12)),
    "mono": dict(ramp=((70, 72, 82), (105, 107, 118), (145, 147, 158), (185, 187, 198), (228, 230, 240)), warm=(255, 255, 255), bg=(8, 8, 9)),
    "dusk": dict(ramp=((60, 45, 150), (140, 60, 175), (230, 90, 145), (255, 140, 110), (255, 192, 140)), warm=(255, 222, 165), bg=(9, 6, 14), mirror=True),
    "solo": dict(ramp=((40, 200, 230), (70, 110, 255), (130, 70, 255), (200, 50, 230), (255, 50, 150)), warm=(255, 150, 70), bg=(6, 5, 12), layout="solo"),
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
S = H / 2160  # sizes below are for 2160 high
rng = np.random.default_rng(7)

BG = np.array(V["bg"], float) / 255
# along the string, far to near
RAMP = [np.array(c, float) / 255 for c in V["ramp"]]
WARM = np.array(V["warm"], float) / 255   # what the light turns into inside the glass


def ramp(t):
    t = min(max(t, 0.0), 1.0) * (len(RAMP) - 1)
    i = min(int(t), len(RAMP) - 2)
    return RAMP[i] + (RAMP[i + 1] - RAMP[i]) * (t - i)


yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

# ── backdrop: dark, with soft glows of the beads' colours ──
img = np.ones((H, W, 3), np.float32) * BG
for (cx, cy, r, t, a) in ((0.66, 0.70, 0.42, 1.0, 0.16), (0.30, 0.45, 0.40, 0.45, 0.10), (0.08, 0.25, 0.30, 0.0, 0.07)):
    d = np.hypot(xx / W - cx, (yy / H - cy) * H / W) / r
    img += ramp(t) * (a * np.exp(-d * d * 3.2))[..., None]
# out-of-focus specks drifting in the dark
for _ in range(int(70)):
    sx, sy = rng.uniform(0, W), rng.uniform(H * 0.15, H)
    sr = rng.uniform(4, 22) * S
    x0, x1, y0, y1 = int(max(sx - sr * 2, 0)), int(min(sx + sr * 2, W)), int(max(sy - sr * 2, 0)), int(min(sy + sr * 2, H))
    if x0 >= x1 or y0 >= y1:
        continue
    dd = np.hypot(xx[y0:y1, x0:x1] - sx, yy[y0:y1, x0:x1] - sy) / sr
    img[y0:y1, x0:x1] += ramp(rng.uniform(0.2, 1.0)) * (np.clip(1.15 - dd, 0, 1) ** 1.5 * rng.uniform(0.03, 0.10))[..., None]

# ── the string: a curve through 3D, projected ──
# a string coming out of the dark at the upper left, curving down through the
# hero (sharp, low on the right of centre), on past the camera at the bottom
N = 9
u = np.linspace(0, 1, N)
px = 0.03 + 0.70 * u ** 1.3
py = 0.25 + 0.47 * u ** 2.3 - 0.05 * np.sin(u * np.pi)
z = 9.0 - 7.6 * u ** 0.75
HERO = N - 2
focus = z[HERO]
beads = []
for i in range(N):
    r = 560 * S / z[i]
    beads.append(dict(x=px[i] * W, y=py[i] * H, r=r, z=z[i], t=0.15 + 0.85 * u[i] ** 0.8, blur=float(abs(z[i] - focus) * 2.4 * S)))
# the near one, past the hero: big, off the bottom edge, out of focus
beads[-1].update(x=0.93 * W, y=1.02 * H, r=360 * S, blur=34 * S, t=1.0)
if V.get("layout") == "solo":
    # one big bead low of centre; a few far ones up behind it, softly
    # (in order along the thread: far ones first)
    beads = [dict(x=fx * W, y=fy * H, r=fr * S, z=6.0 - k, t=ft, blur=(10 - 2 * k) * S)
             for k, (fx, fy, fr, ft) in enumerate(((0.20, 0.30, 38, 0.15), (0.30, 0.36, 52, 0.35), (0.42, 0.44, 70, 0.6)))]
    beads.append(dict(x=0.62 * W, y=0.60 * H, r=470 * S, z=1.0, t=1.0, blur=0.0))


def blur(a, r):
    """Gaussian blur of a 2D float array (separable, reflect at the edges)"""
    if r < 0.3:
        return a
    k = np.arange(-int(r * 3) - 1, int(r * 3) + 2, dtype=np.float32)
    k = np.exp(-k * k / (2 * r * r))
    k /= k.sum()
    n = len(k) // 2
    for axis in (0, 1):
        p = np.pad(a, [(n, n) if ax == axis else (0, 0) for ax in (0, 1)], mode="reflect")
        out = np.zeros_like(a)
        for i, w in enumerate(k):
            out += w * (p[i:i + a.shape[0]] if axis == 0 else p[:, i:i + a.shape[1]])
        a = out
    return a


def layer_add(base, rgb, alpha):
    return base * (1 - alpha[..., None]) + rgb * alpha[..., None]


# the thread: a thin line through the centres, faint, behind the beads
th = np.zeros((H, W), np.float32)
pts = np.array([[b["x"], b["y"]] for b in beads])
fine = []
for k in range(len(pts) - 1):
    for s in np.linspace(0, 1, 40, endpoint=False):
        fine.append(pts[k] * (1 - s) + pts[k + 1] * s)
fine = np.array(fine + [pts[-1]])
thread = Image.new("L", (W, H), 0)

ImageDraw.Draw(thread).line([(float(p[0]), float(p[1])) for p in fine], fill=255, width=max(1, int(2 * S)))
thread = blur(np.asarray(thread, np.float32) / 255, 1.2 * S)
img = layer_add(img, np.array([1.0, 0.85, 0.95]), thread * 0.22)

L = np.array([-0.55, -0.65, 0.52])
L /= np.linalg.norm(L)


def bead_rgba(b):
    """one bead as an RGBA patch (premultiplied), with its box"""
    pad = int(b["r"] * 1.6 + b["blur"] * 3 + 4)
    x0, y0 = int(b["x"] - pad), int(b["y"] - pad)
    x1, y1 = int(b["x"] + pad), int(b["y"] + pad)
    gy, gx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = (gx - b["x"]) / b["r"], (gy - b["y"]) / b["r"]
    d = np.hypot(dx, dy)
    inside = d < 1
    nz = np.sqrt(np.clip(1 - d * d, 0, 1))
    ndl = dx * L[0] + dy * L[1] + nz * L[2]
    col = ramp(b["t"])
    deep = col * 0.10 + BG
    # body: dark glass tinted by its colour, deepest through the middle
    body = deep[None, None] + col[None, None] * (0.10 + 0.30 * np.clip(ndl, 0, 1) + 0.25 * (1 - nz))[..., None]
    # the caustic: light through the glass gathers on the far side, inside the rim
    away = np.clip(-(dx * L[0] + dy * L[1]) / np.maximum(d, 1e-3), 0, 1)
    caustic = np.exp(-((d - 0.72) / 0.16) ** 2) * away ** 2.2
    warm = np.clip(WARM * 0.7 + col * 0.5, 0, 1.2)
    body += warm[None, None] * (caustic * 1.15)[..., None]
    # rim: glass edges catch the light around them
    rim = (1 - nz) ** 3
    body += (col * 0.8 + 0.2)[None, None] * (rim * 1.1)[..., None]
    # highlights: a sharp one and a soft window
    R = 2 * ndl[..., None] * np.stack([dx, dy, nz], -1) - L
    spec = np.clip(R[..., 2], 0, 1)
    body += (spec ** 120 * 1.6 + spec ** 14 * 0.22)[..., None]
    # a softbox reflected up on the left: a soft bright window shape
    wx, wy = dx + 0.42, dy + 0.48
    window = np.clip(1 - np.maximum(np.abs(wx) / 0.20, np.abs(wy) / 0.11) ** 4, 0, 1) * inside
    body += (window * 0.35)[..., None]
    body = np.clip(body, 0, 1.6)
    # coverage, antialiased over about a pixel
    a = np.clip((1 - d) * b["r"] + 0.5, 0, 1)
    rgba = np.dstack([body * a[..., None], a])
    # its glow on the dark around it
    # (fading to nothing before the patch's edge, so no seams)
    edge = np.clip((pad / b["r"] - d) / 0.3, 0, 1)
    glow = np.exp(-np.clip(d - 1, 0, None) * 3.2) * (~inside) * 0.30 * edge
    rgba[..., :3] += (col[None, None] * glow[..., None])
    rgba[..., 3] = np.clip(rgba[..., 3] + glow * 0.0, 0, 1)
    if b["blur"] > 0.6:
        rgba = np.dstack([blur(rgba[..., k], b["blur"]) for k in range(4)])
    return x0, y0, rgba


# far to near
for b in sorted(beads, key=lambda b: -b["z"]):
    x0, y0, p = bead_rgba(b)
    h, w = p.shape[:2]
    ax0, ay0, ax1, ay1 = max(x0, 0), max(y0, 0), min(x0 + w, W), min(y0 + h, H)
    if ax0 >= ax1 or ay0 >= ay1:
        continue
    sub = p[ay0 - y0:ay1 - y0, ax0 - x0:ax1 - x0]
    dst = img[ay0:ay1, ax0:ax1]
    img[ay0:ay1, ax0:ax1] = dst * (1 - sub[..., 3:4]) + sub[..., :3]

# ── bloom: what's bright spills a little ──
bright = np.clip(img - 0.75, 0, None)
small = bright[::4, ::4]   # a wide blur is cheaper at a quarter size
bl = np.dstack([blur(small[..., k], 7 * S) for k in range(3)])
bl = np.asarray(Image.fromarray((np.clip(bl, 0, 4) * 60).astype(np.uint8)).resize((W, H), Image.BILINEAR), np.float32) / 60
img += bl * 0.9

# ── vignette, a darker top for the bar, grain ──
v = np.hypot((xx / W - 0.55) * 1.1, yy / H - 0.55)
img *= (1 - 0.55 * np.clip(v - 0.25, 0, 1) ** 1.4)[..., None]
img *= (0.72 + 0.28 * np.clip(yy / (H * 0.22), 0, 1))[..., None]
img = img / (1 + img * 0.35)  # gentle tone curve so highlights roll off
img += rng.normal(0, 0.012, (H, W, 1)).astype(np.float32)

if V.get("mirror"):
    img = img[:, ::-1]
out = Image.fromarray((np.clip(img, 0, 1) ** (1 / 1.05) * 255 + 0.5).astype(np.uint8), "RGB")
out.save(OUT, quality=93, subsampling=0, optimize=True)
print(OUT, W, H)
