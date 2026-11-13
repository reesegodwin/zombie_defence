# Route 9 Gas's canopy over the pump island (BaseProps "gas_canopy").
# Same footprint as the code version: a 4.2 x 2.8 m roof 3 m up on two posts,
# the island 2.8 x 0.9 m, three pumps along it.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common as C

WHITE = (0.82, 0.82, 0.8)
OFF_WHITE = (0.7, 0.7, 0.68)
ORANGE = (0.85, 0.38, 0.12)
CONCRETE = (0.5, 0.5, 0.48)
PUMP = (0.62, 0.18, 0.12)
FACE = (0.85, 0.85, 0.75)
SCREEN = (0.08, 0.1, 0.1)
DARK = (0.12, 0.12, 0.13)
STEEL = (0.45, 0.46, 0.46)
YELLOW = (0.85, 0.7, 0.15)
LIGHT = (0.95, 0.94, 0.86)

C.reset()

# The island: a kerbed concrete slab with yellow bollards at each end.
C.box((0, 0.08, 0), (2.8, 0.16, 0.9), CONCRETE, bevel=0.03)
C.box((0, 0.17, 0), (2.6, 0.03, 0.72), (0.56, 0.56, 0.54), bevel=0.01)
for sx in (-1.3, 1.3):
    C.cyl((sx, 0.6, 0), 0.07, 0.9, YELLOW, rot=(math.pi / 2, 0, 0), verts=12, bevel=0.015)
    C.cyl((sx, 1.06, 0), 0.07, 0.03, DARK, rot=(math.pi / 2, 0, 0), verts=12)

# Two square posts, with a steel boot at the foot and an orange band.
for sx in (-1.0, 1.0):
    C.box((sx, 1.5, 0), (0.18, 2.9, 0.18), OFF_WHITE, bevel=0.02)
    C.box((sx, 0.35, 0), (0.24, 0.4, 0.24), STEEL, bevel=0.02)
    C.box((sx, 2.3, 0), (0.19, 0.12, 0.19), ORANGE, bevel=0.01)

# The roof: a deep fascia box with a white face and an orange stripe round it,
# a slightly smaller soffit underneath with recessed light panels.
C.box((0, 3.0, 0), (4.2, 0.36, 2.8), WHITE, bevel=0.03, segments=3)
for z in (1.405, -1.405):
    C.box((0, 2.98, z), (4.1, 0.1, 0.03), ORANGE, bevel=0.005)
for x in (2.105, -2.105):
    C.box((x, 2.98, 0), (0.03, 0.1, 2.7), ORANGE, bevel=0.005)
C.box((0, 3.2, 0), (4.0, 0.06, 2.6), OFF_WHITE, bevel=0.02)          # the flat top
C.box((0, 2.81, 0), (3.9, 0.02, 2.5), OFF_WHITE)                     # soffit
for x in (-1.3, 0.0, 1.3):
    for z in (-0.7, 0.7):
        C.box((x, 2.8, z), (0.7, 0.02, 0.32), LIGHT, bevel=0.005)

# Three pumps: a rounded body on a plinth, a display and price window, a
# nozzle in its holster and a hose looping down.
for i in range(3):
    x = -0.7 + i * 0.7
    C.box((x, 0.24, 0), (0.48, 0.08, 0.4), DARK, bevel=0.01)
    C.box((x, 0.75, 0), (0.42, 1.0, 0.36), PUMP, bevel=0.04, segments=3)
    C.box((x, 1.3, 0), (0.44, 0.12, 0.38), WHITE, bevel=0.03)        # its cap
    for z in (0.181, -0.181):
        s = 1 if z > 0 else -1
        C.box((x, 0.98, z), (0.3, 0.26, 0.012), FACE, bevel=0.004)
        C.box((x, 1.02, z + s * 0.004), (0.22, 0.08, 0.008), SCREEN)
        C.box((x - 0.06, 0.93, z + s * 0.004), (0.08, 0.05, 0.008), SCREEN)
        C.box((x + 0.06, 0.93, z + s * 0.004), (0.08, 0.05, 0.008), SCREEN)
        C.box((x, 0.55, z), (0.3, 0.3, 0.01), PUMP)                  # access panel
    # holster and nozzle on the side
    C.box((x + 0.22, 0.85, 0.06), (0.05, 0.12, 0.08), DARK, bevel=0.008)
    C.cyl((x + 0.25, 0.82, 0.06), 0.018, 0.16, DARK, rot=(math.pi / 2, 0, 0), verts=8)
    # the hose: a loop of short tubes from the top of the pump to the nozzle
    pts = []
    for k in range(9):
        t = k / 8
        pts.append((x + 0.2 + 0.1 * math.sin(t * math.pi), 1.15 - 0.75 * math.sin(t * math.pi * 0.9), 0.06))
    for a, b in zip(pts, pts[1:]):
        C.tube(a, b, 0.018, DARK)
    C.sphere(pts[0], 0.02, DARK)

C.export("gas_canopy", ao=0.7, ao_distance=0.6)
