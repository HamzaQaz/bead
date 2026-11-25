#!/usr/bin/env python3
"""Showcase zooms for the demo reel (tools/clip.sh): eases into a part of the
screen, holds, and eases back out, with no jumps or jitter.

    tools/zoom.py IN ZOOMS OUT

ZOOMS has one zoom per line: START SECONDS X Y SCALE (seconds from the start
of IN; X Y the point to zoom towards, in IN's pixels). OUT is written losslessly
(x264 crf 0) at 60 fps, for clip.sh to encode for the web.
"""
import subprocess
import sys

from PIL import Image

FPS = 60
EASE = 1.0   # seconds to zoom in, and to zoom out


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * t * (t * (t * 6 - 15) + 10)


def size_of(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height", "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    w, h = out.strip().split(",")[:2]
    return int(w), int(h)


def at(zooms, t, w, h):
    """(scale, centre x, centre y) at time t."""
    for start, dur, x, y, s in zooms:
        if start <= t <= start + dur:
            k = smooth(min((t - start) / EASE, (start + dur - t) / EASE))
            return 1 + (s - 1) * k, w / 2 + (x - w / 2) * k, h / 2 + (y - h / 2) * k
    return 1.0, w / 2, h / 2


def main():
    src, zfile, dst = sys.argv[1:4]
    zooms = []
    for line in open(zfile):
        p = line.split()
        if len(p) == 5:
            zooms.append(tuple(float(v) for v in p))
    w, h = size_of(src)
    dec = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-i", src, "-vf", f"fps={FPS}",
                            "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", f"{w}x{h}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-crf", "0",
                            "-preset", "ultrafast", dst], stdin=subprocess.PIPE)
    n = w * h * 3
    i = 0
    while True:
        buf = dec.stdout.read(n)
        if len(buf) < n:
            break
        s, cx, cy = at(zooms, i / FPS, w, h)
        if s > 1.001:
            cw, ch = w / s, h / s
            x0 = min(max(cx - cw / 2, 0), w - cw)
            y0 = min(max(cy - ch / 2, 0), h - ch)
            # a fractional box: the frame glides sub-pixel, no stepping
            buf = Image.frombuffer("RGB", (w, h), buf).resize((w, h), Image.LANCZOS,
                                                               box=(x0, y0, x0 + cw, y0 + ch)).tobytes()
        enc.stdin.write(buf)
        i += 1
    enc.stdin.close()
    enc.wait()
    dec.wait()
    print(f"{i} frames, {len(zooms)} zooms", file=sys.stderr)


if __name__ == "__main__":
    main()
