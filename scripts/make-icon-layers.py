#!/usr/bin/env python3
"""Generates Resources/AppIcon.icon (Icon Composer format) for KeyPace.

Canvas: 1024 x 1024 pt, unmasked and square; the system applies the macOS shape.
Layers are opaque white vector keycaps grouped by column. Opacity per layer creates
the left-to-right "pace" fade; the system adds Liquid Glass lighting and depth.
Open the result in Icon Composer to fine-tune; this script only seeds it.
"""
import json, os, sys

out = sys.argv[1]
os.makedirs(os.path.join(out, "Assets"), exist_ok=True)

k, g, r = 139.0, 27.0, 34.0          # key size, gap, corner radius (pt)
row_off = [0.0, 0.45 * k, 0.2 * k]   # keyboard stagger per row
width = row_off[1] + 4 * k + 3 * g
height = 3 * k + 2 * g
x0, y0 = (1024 - width) / 2, (1024 - height) / 2

def key(col, row, span=1):
    x = x0 + row_off[row] + col * (k + g)
    y = y0 + row * (k + g)
    w = span * k + (span - 1) * g
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{k:.1f}" rx="{r}" ry="{r}" fill="#FFFFFF"/>'

# Column layers: rows 1-2 use columns 0..3; row 3 is key, space bar (cols 1-2), key.
layers = {
    "keys-1": [key(0, 0), key(0, 1), key(0, 2)],
    "keys-2": [key(1, 0), key(1, 1)],
    "keys-3": [key(2, 0), key(2, 1), key(1, 2, span=2)],   # space bar travels with col 3
    "keys-4": [key(3, 0), key(3, 1), key(3, 2)],
}
for name, rects in layers.items():
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
           + "".join(rects) + "</svg>\n")
    open(os.path.join(out, "Assets", name + ".svg"), "w").write(svg)

def layer(name, opacity):
    return {"image-name": name + ".svg", "name": name, "opacity": opacity,
            "glass": True, "position": {"scale": 1, "translation-in-points": [0, 0]}}

icon = {
    "fill": {"solid": "srgb:0.16078,0.36078,0.85882,1.00000"},
    "groups": [
        {   # front: the keys "landing" now
            "name": "Front",
            "layers": [layer("keys-4", 1.0), layer("keys-3", 0.82)],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.25},
            "specular": True,
        },
        {   # back: the trail
            "name": "Trail",
            "layers": [layer("keys-2", 0.58), layer("keys-1", 0.36)],
            "shadow": {"kind": "neutral", "opacity": 0.35},
            "translucency": {"enabled": True, "value": 0.5},
            "specular": True,
        },
    ],
    "supported-platforms": {"squares": ["macOS"]},
}
json.dump(icon, open(os.path.join(out, "icon.json"), "w"), indent=2)
print("wrote", out)
