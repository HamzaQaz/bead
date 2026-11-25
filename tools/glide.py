#!/usr/bin/env python3
"""Glide the pointer to X Y over MS milliseconds, easing in and out, the way a
hand moves a mouse (for tools/clip.sh's demo reel).

    tools/glide.py X Y [MS]      (layout coordinates, as hyprctl cursorpos)
"""
import subprocess
import sys
import time


def move(x, y):
    subprocess.run(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{ x = {x:.0f}, y = {y:.0f} }})"],
                   stdout=subprocess.DEVNULL, check=False)


def main():
    tx, ty = float(sys.argv[1]), float(sys.argv[2])
    ms = float(sys.argv[3]) if len(sys.argv) > 3 else 700
    out = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout
    sx, sy = (float(v) for v in out.split(","))
    # a slight arc: hands don't move in straight lines
    dx, dy = tx - sx, ty - sy
    bend = 0.08
    cx, cy = sx + dx / 2 - dy * bend, sy + dy / 2 + dx * bend
    start = time.monotonic()
    while True:
        t = min(1.0, (time.monotonic() - start) * 1000 / ms)
        e = t * t * t * (t * (t * 6 - 15) + 10)  # smootherstep
        # quadratic Bézier through the bend
        x = (1 - e) ** 2 * sx + 2 * (1 - e) * e * cx + e * e * tx
        y = (1 - e) ** 2 * sy + 2 * (1 - e) * e * cy + e * e * ty
        move(x, y)
        if t >= 1:
            break
        time.sleep(1 / 144)


if __name__ == "__main__":
    main()
