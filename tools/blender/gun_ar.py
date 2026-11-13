# The garrison's assault rifle (Guns "ar"). Same size and pivot as the code
# version: it points down +z, the grip at the origin, the bore along y ~ 0.014,
# from the stock's butt at z = -0.24 to the muzzle at z = 0.515 (guns.gd _ar
# still gives those ends, and the game scales the gun to its barrel length).
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common as C

BLACK = (0.1, 0.1, 0.11)
POLY = (0.14, 0.14, 0.15)
STEEL = (0.2, 0.21, 0.22)
WORN = (0.3, 0.31, 0.32)
ALONG = (math.pi / 2 * 0, 0, 0)   # tubes run along z already

C.reset()
B = 0.003   # the usual edge bevel at this size

# Upper receiver with a flat-top rail, the carry handle on it, the ejection
# port and the forward assist; lower receiver with the mag well.
C.box((0, 0.018, 0.02), (0.03, 0.03, 0.17), BLACK, bevel=B)
C.box((0, -0.008, 0.035), (0.028, 0.024, 0.13), POLY, bevel=B)              # lower
C.box((0, -0.03, 0.06), (0.03, 0.03, 0.05), POLY, bevel=B)                  # mag well
C.box((0.0151, 0.018, 0.03), (0.002, 0.012, 0.05), STEEL)                   # ejection port
C.cyl((0.012, 0.024, -0.03), 0.006, 0.03, BLACK, verts=10)                  # forward assist
C.box((0, 0.036, 0.02), (0.016, 0.006, 0.17), BLACK, bevel=0.001)          # rail
for i in range(14):
    C.box((0, 0.04, -0.06 + i * 0.012), (0.018, 0.003, 0.005), STEEL)
C.box((0, 0.052, 0.0), (0.012, 0.022, 0.11), BLACK, bevel=B)               # carry handle
C.box((0, 0.042, 0.0), (0.006, 0.01, 0.07), (0.05, 0.05, 0.05))           # its window
C.box((0, 0.066, -0.045), (0.01, 0.01, 0.02), STEEL, bevel=0.001)          # rear sight
C.box((0, 0.03, -0.072), (0.02, 0.01, 0.025), STEEL, bevel=0.001)          # charging handle

# The handguard: a round tube with cooling vents, a delta ring at the back.
hg = C.cyl((0, 0.016, 0.2), 0.02, 0.2, POLY, verts=16, bevel=0.002)
C.smooth(hg, 30)
for i in range(6):
    for sx in (-1, 1):
        C.box((sx * 0.0195, 0.022, 0.12 + i * 0.03), (0.004, 0.008, 0.016), (0.05, 0.05, 0.05))
C.cyl((0, 0.016, 0.1), 0.023, 0.012, STEEL, verts=16, bevel=0.002)
C.cyl((0, 0.016, 0.3), 0.021, 0.008, STEEL, verts=16)

# The barrel, the front sight post on its A-frame and the flash hider.
bar = C.cyl((0, 0.014, 0.39), 0.008, 0.2, BLACK, verts=12)
C.smooth(bar, 30)
C.box((0, 0.034, 0.32), (0.012, 0.04, 0.016), BLACK, rot=(0.25, 0, 0), bevel=0.001)
C.box((0, 0.058, 0.316), (0.004, 0.024, 0.004), BLACK)
C.cyl((0, 0.014, 0.32), 0.012, 0.02, BLACK, verts=12)
fh = C.cyl((0, 0.014, 0.5), 0.011, 0.03, POLY, verts=12, bevel=0.001)
C.smooth(fh, 30)
for k in range(4):
    a = k / 4 * math.tau + 0.4
    C.box((math.cos(a) * 0.0105, 0.014 + math.sin(a) * 0.0105, 0.505), (0.004, 0.004, 0.016), (0.04, 0.04, 0.04), rot=(0, 0, a))

# A curved 30-round magazine: segments bending forward as they go down.
mag_y, mag_z, tilt = -0.045, 0.062, -0.2
for k in range(5):
    C.box((0, mag_y, mag_z), (0.022, 0.026, 0.034), STEEL, rot=(tilt, 0, 0), bevel=0.002)
    mag_y -= 0.022
    mag_z += 0.022 * math.sin(-tilt) + 0.002
    tilt -= 0.07
C.box((0, mag_y + 0.006, mag_z), (0.024, 0.008, 0.038), BLACK, rot=(tilt, 0, 0), bevel=0.002)   # base plate
C.box((0.0115, -0.06, 0.07), (0.001, 0.05, 0.02), WORN, rot=(-0.3, 0, 0))                      # worn ribs

# Pistol grip with finger grooves, trigger and its guard.
C.box((0, -0.05, -0.045), (0.024, 0.07, 0.032), POLY, rot=(0.3, 0, 0), bevel=0.005, segments=3)
for k in range(3):
    C.box((0, -0.04 - k * 0.016, -0.026 + k * 0.005), (0.026, 0.004, 0.006), BLACK, rot=(0.3, 0, 0))
C.box((0, -0.028, -0.005), (0.006, 0.004, 0.05), BLACK, bevel=0.001)
C.box((0, -0.018, -0.0), (0.003, 0.016, 0.004), STEEL, rot=(0.3, 0, 0))

# The buffer tube and a collapsing stock on it, with a sling loop.
bt = C.cyl((0, 0.008, -0.125), 0.012, 0.12, BLACK, verts=12)
C.smooth(bt, 30)
C.box((0, -0.002, -0.2), (0.03, 0.05, 0.085), POLY, bevel=0.005, segments=3)
C.box((0, -0.03, -0.18), (0.02, 0.03, 0.05), POLY, rot=(-0.4, 0, 0), bevel=0.004)
C.box((0, -0.002, -0.2405), (0.032, 0.06, 0.008), (0.06, 0.06, 0.06), bevel=0.002)   # butt pad
C.tube((0.0, -0.03, -0.215), (0.0, -0.03, -0.195), 0.004, STEEL)

C.export("gun_ar", ao=0.6, ao_distance=0.03, samples=64)
