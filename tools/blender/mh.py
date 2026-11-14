# Reads the MakeHuman base human (CC0: see makehuman/LICENSE.md) for
# build_survivors.py: the base mesh with its helper geometry, the shape
# targets that turn it into a particular man or woman, the game skeleton and
# its skin weights. No add-on needed: these are plain data files.
#
# MakeHuman's own units are decimetres, y up, facing +z. Everything handed
# back from here is in Blender's: metres, z up, facing -y, feet on the floor.
import gzip
import json
import os

import numpy as np

DATA = os.environ.get("MAKEHUMAN_DATA", os.path.join(os.path.dirname(os.path.abspath(__file__)), "makehuman"))
USED = set()   # every data file read, relative to DATA (so only those need keeping in the repo)


def _path(*parts):
    rel = os.path.join(*parts)
    USED.add(rel)
    return os.path.join(DATA, rel)


def to_blender(v):
    """MakeHuman coordinates (an (n, 3) array) to Blender's."""
    return np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1) * 0.1


class Human:
    """The base mesh, shaped. verts: (n, 3) in MakeHuman units until finish()."""

    def __init__(self):
        verts, uvs, faces, face_uvs, face_groups = [], [], [], [], []
        group = ""
        for line in open(_path("3dobjs", "base.obj")):
            if line.startswith("v "):
                verts.append(line.split()[1:4])
            elif line.startswith("vt "):
                uvs.append(line.split()[1:3])
            elif line.startswith("g "):
                group = line.split()[1]
            elif line.startswith("f "):
                parts = [p.split("/") for p in line.split()[1:]]
                faces.append([int(p[0]) - 1 for p in parts])
                face_uvs.append([int(p[1]) - 1 for p in parts])
                face_groups.append(group)
        self.verts = np.array(verts, dtype=np.float64)
        self.uvs = np.array(uvs, dtype=np.float64)
        self.faces = faces
        self.face_uvs = face_uvs
        self.face_groups = face_groups
        # Named runs of vertices: "body", "helper-tights", "joint-pelvis"...
        self.groups = json.load(open(_path("mesh_metadata", "basemesh_vertex_groups.json")))
        self.floor = 0.0

    def group_range(self, name):
        a, b = self.groups[name][0]
        return a, b + 1

    # --- Shape ------------------------------------------------------------
    def target(self, name, weight=1.0):
        """Adds a shape target (a path under targets/, without .target.gz)."""
        if abs(weight) < 1e-4:
            return
        if not os.path.exists(os.path.join(DATA, "targets", name + ".target.gz")):
            return      # some corners of the sliders have no target of their own (they are the base shape)
        idx, off = [], []
        with gzip.open(_path("targets", name + ".target.gz"), "rt") as f:
            for line in f:
                p = line.split()
                if len(p) == 4 and not line.startswith("#"):
                    idx.append(int(p[0]))
                    off.append((float(p[1]), float(p[2]), float(p[3])))
        if idx:
            self.verts[np.array(idx, dtype=int)] += np.array(off) * weight

    def macro(self, gender=1.0, age=0.5, muscle=0.5, weight=0.5, height=0.5, proportions=0.5,
              african=0.0, asian=0.0, cup=0.5, firmness=0.5):
        """The big sliders, as in MakeHuman: gender 0 a woman to 1 a man; age
        0.5 is 25, 1 is 90; the rest 0 to 1 with 0.5 average. african and
        asian: how much of each (the rest caucasian)."""
        def three(x, lo, mid, hi):
            return {hi: (x - 0.5) * 2.0, mid: 1.0 - (x - 0.5) * 2.0} if x > 0.5 else {lo: 1.0 - x * 2.0, mid: x * 2.0}
        genders = {"male": gender, "female": 1.0 - gender}
        if age >= 0.5:
            ages = {"old": (age - 0.5) * 2.0, "young": 1.0 - (age - 0.5) * 2.0}
        else:
            ages = {"young": (age - 0.1875) / 0.3125, "child": 1.0 - (age - 0.1875) / 0.3125}
        muscles = three(muscle, "minmuscle", "averagemuscle", "maxmuscle")
        weights = three(weight, "minweight", "averageweight", "maxweight")
        races = {"african": african, "asian": asian, "caucasian": 1.0 - african - asian}
        heights = {"maxheight": (height - 0.5) * 2.0} if height > 0.5 else {"minheight": 1.0 - height * 2.0}
        props = {"idealproportions": (proportions - 0.5) * 2.0} if proportions > 0.5 else {"uncommonproportions": 1.0 - proportions * 2.0}
        cups = three(cup, "mincup", "averagecup", "maxcup")
        firms = three(firmness, "minfirmness", "averagefirmness", "maxfirmness")
        for g, gv in genders.items():
            for a, av in ages.items():
                for r, rv in races.items():
                    self.target("macrodetails/%s-%s-%s" % (r, g, a), gv * av * rv)
                for m, mv in muscles.items():
                    for w, wv in weights.items():
                        k = gv * av * mv * wv
                        self.target("macrodetails/universal-%s-%s-%s-%s" % (g, a, m, w), k)
                        for h, hv in heights.items():
                            self.target("macrodetails/height/%s-%s-%s-%s-%s" % (g, a, m, w, h), k * hv)
                        for p, pv in props.items():
                            self.target("macrodetails/proportions/%s-%s-%s-%s-%s" % (g, a, m, w, p), k * pv)
                        if g == "female":
                            for c, cv in cups.items():
                                for f, fv in firms.items():
                                    self.target("breast/female-%s-%s-%s-%s-%s" % (a, m, w, c, f), k * cv * fv)

    def finish(self):
        """Into Blender's space, standing on the floor."""
        a, b = self.group_range("body")
        v = to_blender(self.verts)
        self.floor = v[a:b, 2].min()
        v[:, 2] -= self.floor
        self.verts = v

    # --- Parts ------------------------------------------------------------
    def joint(self, name):
        """The middle of a joint's helper cube."""
        a, b = self.group_range(name)
        return self.verts[a:b].mean(axis=0)

    def part(self, group):
        """One group's faces as (verts, faces, uvs per face corner, old vertex indices)."""
        fs = [i for i, g in enumerate(self.face_groups) if g == group]
        used = sorted({v for i in fs for v in self.faces[i]})
        remap = {v: k for k, v in enumerate(used)}
        faces = [[remap[v] for v in self.faces[i]] for i in fs]
        uvs = [[tuple(self.uvs[t]) for t in self.face_uvs[i]] for i in fs]
        return self.verts[used], faces, uvs, np.array(used)

    # --- Skeleton ---------------------------------------------------------
    def rig(self, name="game_engine"):
        """{bone: {"head", "tail", "roll", "parent"}} for this body."""
        raw = json.load(open(_path("rigs", "standard", "rig.%s.json" % name)))
        bones = {}
        for bone, d in raw.items():
            ends = {}
            for end in ("head", "tail"):
                e = d[end]
                if e.get("strategy") == "CUBE" and e.get("cube_name") in self.groups:
                    ends[end] = self.joint(e["cube_name"])
                elif e.get("strategy") == "VERTEX":
                    ends[end] = self.verts[e["vertex_index"]]
                elif e.get("strategy") == "MEAN":
                    ends[end] = self.verts[e["vertex_indices"]].mean(axis=0)
                else:
                    p = np.array(e["default_position"])
                    ends[end] = p - np.array([0, 0, self.floor])
            bones[bone] = {"head": ends["head"], "tail": ends["tail"], "roll": d.get("roll", 0.0), "parent": d.get("parent") or None}
        return bones

    def weights(self, name="game_engine"):
        """{bone: [(vertex index, weight), ...]} for every vertex of the base mesh."""
        return json.load(open(_path("rigs", "standard", "weights.%s.json" % name)))["weights"]


def fit_proxy(human, folder, name):
    """A separate mesh fitted onto the base mesh (MakeHuman's .mhclo: each of
    its points rides three of the body's): (verts, faces, uvs per corner)."""
    refs, scale = [], {}
    in_verts = False
    for line in open(_path(folder, name + ".mhclo")):
        p = line.split()
        if not p or line.startswith("#"):
            continue
        if p[0] in ("x_scale", "y_scale", "z_scale"):
            scale[p[0][0]] = (int(p[1]), int(p[2]), float(p[3]))
        elif p[0] == "verts":
            in_verts = True
        elif in_verts and len(p) == 9:
            refs.append([float(x) for x in p])
        elif in_verts and len(p) == 1 and p[0].isdigit():
            refs.append([float(p[0]), float(p[0]), float(p[0]), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
        elif in_verts and not p[0][0].isdigit():
            in_verts = False
    refs = np.array(refs)
    v = human.verts            # already Blender space: MakeHuman x, y, z are x, z, -y here
    def span(axis, comp):
        a, b, den = scale[axis]
        return abs(v[a, comp] - v[b, comp]) / den
    sx, sy, sz = span("x", 0), span("y", 2), span("z", 1)
    i = refs[:, 0:3].astype(int)
    pos = v[i[:, 0]] * refs[:, 3:4] + v[i[:, 1]] * refs[:, 4:5] + v[i[:, 2]] * refs[:, 5:6]
    pos += np.stack([refs[:, 6] * sx, -refs[:, 8] * sz, refs[:, 7] * sy], axis=1)
    verts_n, uvs, faces, face_uvs = 0, [], [], []
    for line in open(_path(folder, name + ".obj")):
        if line.startswith("v "):
            verts_n += 1
        elif line.startswith("vt "):
            uvs.append(tuple(float(x) for x in line.split()[1:3]))
        elif line.startswith("f "):
            parts = [q.split("/") for q in line.split()[1:]]
            faces.append([int(q[0]) - 1 for q in parts])
            face_uvs.append([uvs[int(q[1]) - 1] for q in parts])
    assert verts_n == len(pos), (verts_n, len(pos))
    return pos, faces, face_uvs
