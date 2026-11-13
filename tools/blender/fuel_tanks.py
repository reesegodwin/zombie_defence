# Tank Farm's landmark behind the base (Backdrop "fuel_tanks"): two big round
# tanks with domed roofs on a walled concrete pad, stairs up the side and a
# railing round the top, pipework with valves between them, a control hut.
# Same footprint as the code version: the pad 14 x 7.5 m, tanks 3 m in radius
# at x = +-3.3, their walls 4.6 m tall.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import common as C

TANK = (0.72, 0.71, 0.66)
SEAM = (0.6, 0.59, 0.55)
PAD = (0.45, 0.45, 0.43)
WALL = (0.4, 0.4, 0.38)
STEEL = (0.32, 0.33, 0.33)
RAIL = (0.78, 0.68, 0.2)
PIPE = (0.5, 0.48, 0.45)
VALVE = (0.62, 0.16, 0.1)
HUT = (0.8, 0.78, 0.72)
ROOF = (0.3, 0.3, 0.3)
SIGN = (0.85, 0.7, 0.15)
DARK = (0.1, 0.1, 0.11)
RUST = (0.45, 0.28, 0.17)
UP = (math.pi / 2, 0, 0)   # a tube along z stood upright

C.reset()

# The pad and its bund wall (to hold a spill).
C.box((0, 0.15, 0), (14.0, 0.3, 7.5), PAD, bevel=0.05)
for z in (3.7, -3.7):
    C.box((0, 0.75, z), (14.0, 0.9, 0.25), WALL, bevel=0.05)
for x in (7.0, -7.0):
    C.box((x, 0.75, 0), (0.25, 0.9, 7.5), WALL, bevel=0.05)

for i, x in enumerate((-3.3, 3.3)):
    # The shell: a smooth drum with welded seams and a rusty foot ring.
    shell = C.cyl((x, 2.6, 0), 3.0, 4.6, TANK, rot=UP, verts=64, bevel=0.06, segments=3)
    C.smooth(shell, 30)
    for h in (1.45, 2.6, 3.75):
        r = C.cyl((x, h, 0), 3.025, 0.05, SEAM, rot=UP, verts=64)
        C.smooth(r, 30)
    foot = C.cyl((x, 0.45, 0), 3.06, 0.3, RUST, rot=UP, verts=64, bevel=0.03)
    C.smooth(foot, 30)
    # The roof: a shallow dome and a vent on top.
    C.sphere((x, 4.9, 0), 3.0, (0.76, 0.75, 0.7), scale=(1.0, 0.22, 1.0), segs=48, rings=24)
    C.cyl((x, 5.75, 0), 0.25, 0.3, STEEL, rot=UP, verts=16, bevel=0.03)
    C.cyl((x, 5.95, 0), 0.38, 0.08, STEEL, rot=UP, verts=16, bevel=0.02)
    # A railing round the top edge.
    posts = 28
    for k in range(posts):
        a = k / posts * math.tau
        p = (x + math.cos(a) * 2.9, 5.15, math.sin(a) * 2.9)
        C.tube((p[0], 4.9, p[2]), (p[0], 5.55, p[2]), 0.025, RAIL, verts=6)
    for h in (5.25, 5.55):
        ring = 48
        for k in range(ring):
            a0, a1 = k / ring * math.tau, (k + 1) / ring * math.tau
            C.tube((x + math.cos(a0) * 2.9, h, math.sin(a0) * 2.9), (x + math.cos(a1) * 2.9, h, math.sin(a1) * 2.9), 0.025, RAIL, verts=6)
    # Stairs winding up the shell: treads on brackets, with a handrail.
    steps = 22
    start = math.pi * 0.95 if i == 0 else math.pi * 0.05   # the outer front quarter, where the camera sees them
    turn = -1 if i == 0 else 1
    rail_pts = []
    for k in range(steps):
        a = start + turn * k * 0.07
        h = 0.55 + k * 4.35 / steps
        cx, cz = x + math.cos(a) * 3.35, math.sin(a) * 3.35
        C.box((cx, h, cz), (0.65, 0.05, 0.28), STEEL, rot=(0, -a, 0), bevel=0.01)
        C.tube((x + math.cos(a) * 3.0, h - 0.02, math.sin(a) * 3.0), (cx + math.cos(a) * 0.3, h - 0.02, cz + math.sin(a) * 0.3), 0.02, STEEL, verts=6)
        rail_pts.append((x + math.cos(a) * 3.68, h + 0.9, math.sin(a) * 3.68))
        if k % 3 == 0:
            C.tube((x + math.cos(a) * 3.68, h, math.sin(a) * 3.68), rail_pts[-1], 0.022, RAIL, verts=6)
    for a, b in zip(rail_pts, rail_pts[1:]):
        C.tube(a, b, 0.025, RAIL, verts=6)
    # A manway near the foot, facing the hut.
    ma = 0.5 if i == 0 else math.pi - 0.5
    C.cyl((x + math.cos(ma) * 3.0, 1.2, math.sin(ma) * 3.0), 0.4, 0.12, SEAM, rot=(0, math.pi / 2 - ma, 0), verts=24, bevel=0.02)
    # A big painted number on the side facing the camera (the inner front quarter).
    na = 1.15 if i == 0 else math.pi - 1.15
    face = (0, math.pi / 2 - na, 0)
    C.box((x + math.cos(na) * 3.01, 3.0, math.sin(na) * 3.01), (0.9, 1.1, 0.02), (0.25, 0.27, 0.3), rot=face)
    C.box((x + math.cos(na) * 3.03, 3.0, math.sin(na) * 3.03), (0.18, 0.8, 0.02) if i == 0 else (0.5, 0.18, 0.02), TANK, rot=face)

# The pipe run between the tanks, on little stands, with flanges and a valve.
C.cyl((0, 1.0, 0), 0.18, 1.6, PIPE, rot=(0, math.pi / 2, 0), verts=20, bevel=0.02)
for sx in (-0.75, 0.75):
    C.cyl((sx, 1.0, 0), 0.26, 0.06, PIPE, rot=(0, math.pi / 2, 0), verts=20, bevel=0.01)
C.box((0, 0.6, 0), (0.25, 0.7, 0.4), STEEL, bevel=0.02)
C.tube((0, 1.18, 0), (0, 1.55, 0), 0.04, STEEL)
C.cyl((0, 1.58, 0), 0.24, 0.04, VALVE, rot=UP, verts=24)
for k in range(3):
    a = k / 3 * math.pi
    C.tube((math.cos(a) * 0.23, 1.58, math.sin(a) * 0.23), (-math.cos(a) * 0.23, 1.58, -math.sin(a) * 0.23), 0.015, VALVE, verts=6)
# And a pipe off each tank to the loading point by the hut.
C.tube((3.3 + 2.95, 0.8, 1.0), (5.4, 0.8, 2.6), 0.14, PIPE, verts=16)
C.tube((5.4, 0.8, 2.6), (5.4, 1.4, 2.6), 0.14, PIPE, verts=16)
C.cyl((5.4, 1.35, 2.6), 0.2, 0.08, VALVE, rot=UP, verts=20)

# The control hut: a little block with a door, a window and a sloped roof.
C.box((6.2, 1.3, 2.9), (1.4, 1.6, 1.2), HUT, bevel=0.03)
C.box((6.2, 2.18, 2.9), (1.6, 0.1, 1.45), ROOF, rot=(0, 0, 0.08), bevel=0.02)
C.box((6.2, 1.15, 3.505), (0.5, 1.15, 0.02), (0.35, 0.4, 0.42), bevel=0.005)    # door
C.box((5.5 - 0.005, 1.5, 2.9), (0.02, 0.45, 0.6), DARK)                          # window
C.box((6.905, 1.5, 2.9), (0.02, 0.4, 0.4), SIGN)                                 # warning sign
C.box((6.915, 1.5, 2.9), (0.01, 0.2, 0.06), DARK)

C.export("fuel_tanks", ao=0.7, ao_distance=2.0, samples=48)
