"""Find the saturated red and blue marker blobs (Workspace.OpticsTest scale boards) in Studio viewport captures.
Prints every blob: colour, centroid (x, y), area, bbox, mean colour. Used to measure the rendered lens magnification:
marker spacing inside the lens / the same spacing at the hip (Roblox/Tests/Optics/README.md).
Run: blender -b --factory-startup --python markers.py -- <png> [<png> ...]
"""
import sys

import bpy
import numpy as np

paths = sys.argv[sys.argv.index("--") + 1:]


def label(mask):
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]:
            continue
        n += 1
        stack = [(y0, x0)]
        lab[y0, x0] = n
        while stack:
            y, x = stack.pop()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    stack.append((yy, xx))
    return lab, n


for p in paths:
    img = bpy.data.images.load(p)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3] * 255
    bpy.data.images.remove(img)
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    masks = {
        "red": (r > 120) & (g < 70) & (b < 70) & (r > 2.2 * g),
        "blue": (b > 120) & (r < 70) & (g < 110) & (b > 1.8 * g),
    }
    print("IMAGE", p, w, h)
    for name, m in masks.items():
        lab, n = label(m)
        for i in range(1, n + 1):
            yy, xx = np.nonzero(lab == i)
            if len(xx) < 4:
                continue
            col = px[yy, xx].mean(axis=0)
            print("BLOB", name, "cx %.2f cy %.2f area %d bbox %d %d %d %d col %d %d %d" % (
                xx.mean(), yy.mean(), len(xx), xx.min(), xx.max(), yy.min(), yy.max(), col[0], col[1], col[2]))
