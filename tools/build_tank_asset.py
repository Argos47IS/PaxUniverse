"""Build the original Pax Units Atlas MBT blockout+ asset, without third-party tools.

Metres; right-handed, Y up, vehicle forward -Z. Geometry is intentionally
material-coloured (no external textures), and the turret / gun are separate
pivoted nodes. Re-running this file is deterministic.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "mods" / "pax_units" / "models" / "atlas_mbt.glb"
PAINT, METAL, RUBBER, MARKING, OPTIC = range(5)
MATERIALS = [
    {"name": "Olive armour", "pbrMetallicRoughness": {"baseColorFactor": [.10, .125, .065, 1], "metallicFactor": .32, "roughnessFactor": .66}},
    {"name": "Graphite steel", "pbrMetallicRoughness": {"baseColorFactor": [.105, .125, .12, 1], "metallicFactor": .65, "roughnessFactor": .49}},
    {"name": "Track rubber and recesses", "pbrMetallicRoughness": {"baseColorFactor": [.039, .048, .046, 1], "metallicFactor": .03, "roughnessFactor": .91}},
    {"name": "Blue grey identification", "pbrMetallicRoughness": {"baseColorFactor": [.37, .54, .61, 1], "metallicFactor": .15, "roughnessFactor": .62}},
    {"name": "Coated optics and lamps", "pbrMetallicRoughness": {"baseColorFactor": [.22, .48, .61, 1], "metallicFactor": .5, "roughnessFactor": .2}, "emissiveFactor": [.025, .06, .08]},
]


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def norm(v):
    length = math.sqrt(dot(v, v))
    return tuple(x / length for x in v)


def average(points):
    return tuple(sum(p[i] for p in points) / len(points) for i in range(3))


class Mesh:
    def __init__(self, name, pivot):
        self.name, self.pivot = name, pivot
        self.groups = {}

    def face(self, points, material, outward=None):
        pts = list(points)
        n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])))
        if outward is not None and dot(n, outward) < 0:
            pts.reverse()
            n = tuple(-v for v in n)
        group = self.groups.setdefault(material, {"positions": [], "normals": [], "indices": []})
        start = len(group["positions"])
        group["positions"].extend(sub(p, self.pivot) for p in pts)
        group["normals"].extend([n] * len(pts))
        for i in range(1, len(pts)-1):
            group["indices"].extend((start, start+i, start+i+1))

    def solid(self, vertices, faces, material):
        center = average(vertices)
        for face in faces:
            pts = [vertices[i] for i in face]
            self.face(pts, material, sub(average(pts), center))

    def bevel_box(self, center, size, bevel, material, angle=0):
        """True planar bevel: six inset faces, 12 chamfer strips, eight corners."""
        half = tuple(v/2 for v in size)
        b = min(bevel, min(half)*.9)
        ca, sa = math.cos(angle), math.sin(angle)

        def transform(v):
            return (center[0]+ca*v[0]+sa*v[2], center[1]+v[1], center[2]-sa*v[0]+ca*v[2])

        def emit(pts):
            transformed = [transform(p) for p in pts]
            self.face(transformed, material, sub(average(transformed), center))

        for axis in range(3):
            others = [a for a in range(3) if a != axis]
            for sign in (-1, 1):
                pts = []
                for u, v in ((-1,-1), (1,-1), (1,1), (-1,1)):
                    p = [0.0]*3
                    p[axis] = sign*half[axis]
                    p[others[0]] = u*(half[others[0]]-b)
                    p[others[1]] = v*(half[others[1]]-b)
                    pts.append(p)
                emit(pts)
        for a, baxis in ((0,1), (0,2), (1,2)):
            free = 3-a-baxis
            for saxis in (-1, 1):
                for taxis in (-1, 1):
                    pts=[]
                    for sfree, inset_first in ((-1,False), (1,False), (1,True), (-1,True)):
                        p = [0.0]*3
                        p[free] = sfree*(half[free]-b)
                        p[a] = saxis*(half[a]-(b if inset_first else 0))
                        p[baxis] = taxis*(half[baxis]-(0 if inset_first else b))
                        pts.append(p)
                    emit(pts)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    signs = (sx, sy, sz)
                    pts=[]
                    for keep in range(3):
                        pts.append([signs[a]*(half[a]-(0 if a == keep else b)) for a in range(3)])
                    emit(pts)

    def rings(self, rings, material):
        vertices = [p for ring in rings for p in ring]
        n = len(rings[0])
        faces = [tuple(range(n-1, -1, -1)), tuple((len(rings)-1)*n+i for i in range(n))]
        for r in range(len(rings)-1):
            for j in range(n):
                faces.append((r*n+j, r*n+(j+1)%n, (r+1)*n+(j+1)%n, (r+1)*n+j))
        self.solid(vertices, faces, material)

    def cylinder(self, start, end, radius, material, sides=16, end_radius=None, cap=True):
        axis = norm(sub(end, start))
        reference = (0, 1, 0) if abs(axis[1]) < .9 else (1, 0, 0)
        u = norm(cross(axis, reference))
        v = cross(axis, u)
        radii = (radius, radius if end_radius is None else end_radius)
        rings = []
        for p, rad in zip((start, end), radii):
            rings.append([tuple(p[j]+rad*(math.cos(i*2*math.pi/sides)*u[j]+math.sin(i*2*math.pi/sides)*v[j]) for j in range(3)) for i in range(sides)])
        if cap:
            self.rings(rings, material)
        else:
            for i in range(sides):
                pts = [rings[0][i], rings[0][(i+1)%sides], rings[1][(i+1)%sides], rings[1][i]]
                self.face(pts, material, sub(average(pts), average((start,end))))


def octagon(cx, y, cz, width, length, corner):
    x, z = width/2, length/2
    return [(cx+px, y, cz+pz) for px,pz in ((-x+corner,-z),(x-corner,-z),(x,-z+corner),(x,z-corner),(x-corner,z),(-x+corner,z),(-x,z-corner),(-x,-z+corner))]


def build_geometry():
    hull = Mesh("Hull", (0, 0, 0))
    turret = Mesh("Turret", (0, 1.75, -.2))
    gun = Mesh("Gun", (0, 2.14, -1.22))

    # Broad welded lower body, sharply sloped glacis, and smaller raised rear deck.
    hull.rings([
        octagon(0,.38,.16,2.72,5.96,.45),
        octagon(0,1.03,0,3.35,6.92,.48),
        octagon(0,1.61,.39,3.30,5.56,.34),
        octagon(0,1.70,.41,3.20,5.43,.30),
    ], PAINT)
    hull.bevel_box((0,1.49,2.52),(2.86,.4,1.14),.06,PAINT)

    # Continuous track bands are closed annular meshes, with individually shaped shoes.
    for side in (-1,1):
        x = side*1.49
        loop=[]
        for step in range(13):
            a = math.pi*step/12
            loop.append((.63+.61*math.cos(a),2.69+.61*math.sin(a)))
        for step in range(13):
            a = math.pi+math.pi*step/12
            loop.append((.63+.61*math.cos(a),-2.69+.61*math.sin(a)))
        # Ordered perimeter in Y/Z; top and bottom bridge the semicircles.
        inner=[]
        for y,z in loop:
            if z > 2.69: inward=(y-.63,z-2.69)
            elif z < -2.69: inward=(y-.63,z+2.69)
            else: inward=(y-.63,0)
            length=math.hypot(*inward)
            inner.append((y-.115*inward[0]/length,z-.115*inward[1]/length))
        for i in range(len(loop)):
            j=(i+1)%len(loop)
            outer_a,outer_b=loop[i],loop[j]
            inner_a,inner_b=inner[i],inner[j]
            vs=[(x+dx,y,z) for dx in (-.32,.32) for y,z in (outer_a,outer_b,inner_b,inner_a)]
            hull.solid(vs,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(3,2,6,7)],RUBBER)
        # Sample equal arc-length links all around a stadium path.
        straight=5.38
        arc=math.pi*.61
        perimeter=2*straight+2*arc
        count=72
        for k in range(count):
            t=k*perimeter/count
            if t<straight: y,z,dy,dz=1.24,-2.69+t,0,1
            elif t<straight+arc:
                a=(t-straight)/.61
                y,z,dy,dz=.63+.61*math.cos(a),2.69+.61*math.sin(a),-math.sin(a),math.cos(a)
            elif t<2*straight+arc: y,z,dy,dz=.02,2.69-(t-straight-arc),0,-1
            else:
                a=math.pi+(t-2*straight-arc)/.61
                y,z,dy,dz=.63+.61*math.cos(a),-2.69+.61*math.sin(a),-math.sin(a),math.cos(a)
            radial=(dz,-dy)
            length=perimeter/count*.86
            vs=[]
            for dx in (-.345,.345):
                for normal,tangent in ((-.004,-length/2),(.032,-length/2),(.032,length/2),(-.004,length/2)):
                    vs.append((x+dx,y+radial[0]*normal+dy*tangent,z+radial[1]*normal+dz*tangent))
            hull.solid(vs,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],METAL)
        # Recessed wheels with dark tires, olive centres, steel hubcaps and bolts.
        for zi in (-2.48,-1.66,-.83,0,.83,1.66,2.48):
            hull.cylinder((x-.29,.56,zi),(x+.29,.56,zi),.465,RUBBER,20)
            outer=x+side*.3
            hull.cylinder((outer,.56,zi),(outer+side*.035,.56,zi),.352,PAINT,20)
            hull.cylinder((outer+side*.04,.56,zi),(outer+side*.075,.56,zi),.145,METAL,16)
            for a in range(6):
                angle=a*math.tau/6
                yy=.56+.238*math.sin(angle)
                zz=zi+.238*math.cos(angle)
                hull.cylinder((outer+side*.035,yy,zz),(outer+side*.055,yy,zz),.022,METAL,6)
        # Floating side armour leaves the bottom 2/3 of the running gear visible.
        for zi in (-2.5,-1.49,-.48,.53,1.54,2.55):
            hull.bevel_box((side*1.79,1.30,zi),(.14,.66,.96),.055,PAINT)
            hull.bevel_box((side*1.86,1.48,zi),(.055,.14,.60),.018,METAL)
            for zz in (-.31,.31):
                hull.cylinder((side*1.868,1.18,zi+zz),(side*1.885,1.18,zi+zz),.027,METAL,6)
        hull.bevel_box((side*1.58,1.67,.26),(.40,.11,5.90),.03,PAINT)
        # Identification stripe crosses side skirt; two parallel thin bars on frontal glacis.
        hull.bevel_box((side*1.867,1.30,-1.49),(.014,.47,.115),.005,MARKING)
        hull.bevel_box((side*1.867,1.30,-1.27),(.014,.47,.115),.005,MARKING)
        # Headlight recesses; raised guards deliberately silhouette well at map scale.
        hull.bevel_box((side*1.25,1.39,-2.65),(.38,.22,.29),.04,METAL)
        hull.bevel_box((side*1.25,1.4,-2.802),(.255,.108,.024),.009,OPTIC)
        hull.bevel_box((side*1.25,1.55,-2.65),(.43,.045,.35),.015,PAINT)
        hull.cylinder((side*1.05,.77,-3.13),(side*1.05,.77,-3.27),.10,METAL,12)
        hull.bevel_box((side*1.12,1.57,2.54),(.42,.08,.80),.025,PAINT)

    # Sloped glacis has longitudinal strips whose vertices follow its actual plane.
    for stripe_x in (.30,.58):
        hull.face([(stripe_x-.075,1.101,-3.35),(stripe_x+.075,1.101,-3.35),(stripe_x+.075,1.607,-2.37),(stripe_x-.075,1.607,-2.37)],MARKING,(0,1,-1))
    # Driver hatch, periscopes, deck fasteners and paired rear louvres.
    hull.bevel_box((-.75,1.718,-1.86),(.64,.06,.68),.075,PAINT)
    for xi in (-.99,-.76,-.53):
        hull.bevel_box((xi,1.77,-2.05),(.17,.08,.12),.012,METAL)
        hull.bevel_box((xi,1.783,-2.115),(.125,.034,.014),.004,OPTIC)
    for sx in (-1,1):
        hull.bevel_box((sx*.64,1.735,2.44),(1.07,.035,.98),.035,METAL)
        for zi in range(10):
            hull.bevel_box((sx*.64,1.764,2.02+zi*.093),(.98,.037,.043),.008,PAINT)
        # Exhaust vents at rear vertical face.
        for zi in range(5):
            hull.bevel_box((sx*.72,1.23+zi*.065,3.109),(.92,.034,.026),.008,METAL)
    for x in (-1.3,1.3):
        for z in (-1.35,-.50,.35,1.2):
            hull.cylinder((x,1.71,z),(x,1.746,z),.031,METAL,6)

    # Turret ring plus multi-plane wedge turret: chamfered upper corners and cheeks.
    turret.cylinder((0,1.69,-.18),(0,1.86,-.18),1.12,METAL,32)
    turret.rings([
        octagon(0,1.87,-.09,2.76,2.93,.35),
        octagon(0,2.38,-.02,2.77,2.70,.43),
        octagon(0,2.66,.08,2.22,2.18,.32),
        octagon(0,2.71,.09,2.08,2.02,.27),
    ],PAINT)
    for side in (-1,1):
        # Forehead applique wedge independent from the hull's primary solid.
        verts=[(side*.27,1.97,-1.46),(side*1.27,1.97,-1.36),(side*1.19,2.40,-1.21),(side*.29,2.45,-1.28),
               (side*.30,2.04,-1.68),(side*1.21,2.04,-1.55),(side*1.04,2.38,-1.40),(side*.31,2.41,-1.48)]
        turret.solid(verts,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],PAINT)
        # Each stripe is applied to the flat outward-sloping cheek surface.
        if side == 1:
            for xx in (.64,.87):
                turret.face([(xx-.047,2.055,-1.635+(xx-.3)*.14),(xx+.047,2.055,-1.635+(xx-.3)*.14),(xx+.047,2.386,-1.474+(xx-.3)*.095),(xx-.047,2.386,-1.474+(xx-.3)*.095)],MARKING,(0,.2,-1))
        # Two broad stand-off cheek plates follow both facets of the turret side.
        # Clear seams and at least 5 mm clearance avoid coplanar surfaces.
        for panel_z in (-.32,.40):
            plates=[]
            for y,inside,half_z in ((2.16,1.390,.315),(2.38,1.392,.304),(2.52,1.254,.285)):
                plates.append([
                    (side*inside,y,panel_z-half_z),
                    (side*(inside+.067),y,panel_z-half_z),
                    (side*(inside+.067),y,panel_z+half_z),
                    (side*inside,y,panel_z+half_z),
                ])
            # Each half is convex; its own centroid gives correct inward-side
            # normals even around the crease of this narrow bent armour plate.
            turret.rings(plates[:2],PAINT)
            turret.rings(plates[1:],PAINT)
        turret.bevel_box((side*1.40,2.13,1.04),(.18,.32,.51),.05,PAINT)
        turret.bevel_box((side*1.49,2.15,1.04),(.025,.06,.32),.009,METAL)
        # Compact smoke dischargers, tilted out and up; distinguishable groups of three.
        for zi in range(3):
            a=(side*1.26,2.28,-.04+zi*.22)
            b=(side*1.51,2.49,-.16+zi*.22)
            turret.cylinder(a,b,.063,METAL,10)
        # Rear stowage boxes and grab rails.
        turret.bevel_box((side*.66,2.16,1.47),(1.03,.54,.37),.06,PAINT)
        turret.bevel_box((side*.66,2.19,1.666),(.20,.085,.028),.01,METAL)
        turret.cylinder((side*.95,2.46,.77),(side*.95,2.46,1.24),.025,METAL,8)
    turret.cylinder((-.49,2.704,.30),(-.49,2.78,.30),.38,PAINT,24)
    turret.cylinder((.52,2.704,.38),(.52,2.82,.38),.32,PAINT,24)
    for x,z in ((-.49,.3),(.52,.38)):
        turret.bevel_box((x,2.81,z),(.23,.045,.055),.01,METAL)
    # Panoramic sight, forward optics, and a folded low remote station.
    turret.cylinder((-.76,2.66,-.52),(-.76,2.88,-.52),.093,METAL,12)
    turret.bevel_box((-.76,2.94,-.52),(.31,.24,.29),.035,PAINT)
    turret.bevel_box((-.76,2.95,-.672),(.205,.13,.024),.014,OPTIC)
    turret.bevel_box((.48,2.71,-.65),(.34,.16,.30),.035,METAL)
    turret.bevel_box((.48,2.73,-.808),(.225,.075,.023),.008,OPTIC)
    # Antennas are short and thicker than real-life so they survive map rendering.
    for x in (-.80,.82):
        turret.cylinder((x,2.63,.83),(x,2.77,.83),.057,METAL,10)
        turret.cylinder((x,2.77,.83),(x,3.24,.83),.018,METAL,8,end_radius=.011)

    # Mantlet, thermal sleeve, bore evacuator and a genuinely open muzzle annulus.
    gun.bevel_box((0,2.19,-1.48),(.60,.52,.48),.12,PAINT)
    gun.cylinder((0,2.17,-1.69),(0,2.17,-2.10),.235,METAL,20,end_radius=.185)
    gun.cylinder((0,2.17,-2.08),(0,2.17,-3.20),.151,PAINT,20,end_radius=.139)
    gun.cylinder((0,2.17,-3.15),(0,2.17,-3.64),.191,PAINT,20,end_radius=.169)
    gun.cylinder((0,2.17,-3.62),(0,2.17,-5.84),.121,PAINT,20,end_radius=.102)
    for z,r in ((-2.14,.159),(-2.95,.151),(-3.75,.13),(-5.35,.12)):
        gun.cylinder((0,2.17,z+.034),(0,2.17,z-.034),r,METAL,20)
    gun.cylinder((0,2.17,-5.81),(0,2.17,-6.02),.135,METAL,20,end_radius=.123,cap=False)
    for i in range(20):
        a,b=i*math.tau/20,(i+1)*math.tau/20
        points=[(r*math.cos(t),2.17+r*math.sin(t),-6.023) for r,t in ((.123,a),(.123,b),(.077,b),(.077,a))]
        gun.face(points,PAINT,(0,0,-1))
    gun.cylinder((0,2.17,-5.83),(0,2.17,-5.841),.078,METAL,20)
    # Inner bore faces point inward and create visible parallax rather than a black disk.
    for i in range(20):
        a,b=i*math.tau/20,(i+1)*math.tau/20
        p=[(.077*math.cos(t),2.17+.077*math.sin(t),z) for t,z in ((a,-6.02),(b,-6.02),(b,-5.84),(a,-5.84))]
        gun.face(p,METAL,(-math.cos((a+b)/2),-math.sin((a+b)/2),0))
    meshes = [hull,turret,gun]
    # Inclined track shoes extend slightly past the ideal stadium; ground exactly
    # at zero using a shared root-space lift while preserving articulated pivots.
    ground = min(p[1]+m.pivot[1] for m in meshes for g in m.groups.values() for p in g["positions"])
    for mesh in meshes:
        mesh.pivot = (mesh.pivot[0],mesh.pivot[1]-ground,mesh.pivot[2])
    return meshes


def write_glb(meshes):
    blob=bytearray()
    doc={"asset":{"version":"2.0","generator":"Pax Units original procedural mesh builder 1.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Atlas MBT","children":[1]}],"meshes":[],"materials":MATERIALS,"accessors":[],"bufferViews":[],"buffers":[{}]}
    bounds=[]

    def accessor(values, kind, component, target):
        while len(blob)%4: blob.append(0)
        offset=len(blob)
        flat=[x for v in values for x in v] if kind=="VEC3" else values
        blob.extend(struct.pack("<"+("f" if component==5126 else "I")*len(flat),*flat))
        view=len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":len(blob)-offset,"target":target})
        a={"bufferView":view,"componentType":component,"count":len(values),"type":kind}
        if kind=="VEC3":
            a["min"]=[min(v[i] for v in values) for i in range(3)]
            a["max"]=[max(v[i] for v in values) for i in range(3)]
        index=len(doc["accessors"])
        doc["accessors"].append(a)
        return index

    for mi,mesh in enumerate(meshes):
        primitives=[]
        for material,g in sorted(mesh.groups.items()):
            for p in g["positions"]:
                assert all(math.isfinite(v) for v in p)
                bounds.append(tuple(p[i]+mesh.pivot[i] for i in range(3)))
            assert all(abs(dot(n,n)-1)<1e-5 for n in g["normals"])
            assert len(g["indices"])%3==0 and max(g["indices"])<len(g["positions"])
            primitives.append({"attributes":{"POSITION":accessor(g["positions"],"VEC3",5126,34962),"NORMAL":accessor(g["normals"],"VEC3",5126,34962)},"indices":accessor(g["indices"],"SCALAR",5125,34963),"material":material,"mode":4})
        doc["meshes"].append({"name":mesh.name+" geometry","primitives":primitives})
        parent_pivot=meshes[mi-1].pivot if mi>0 else (0,0,0)
        node={"name":mesh.name,"mesh":mi,"translation":list(sub(mesh.pivot,parent_pivot))}
        if mi<2: node["children"]=[mi+2]
        doc["nodes"].append(node)
    doc["buffers"][0]["byteLength"]=len(blob)
    encoded=json.dumps(doc,ensure_ascii=False,separators=(",",":")).encode()
    encoded+=b" "*((-len(encoded))%4)
    blob+=b"\0"*((-len(blob))%4)
    binary=struct.pack("<III",0x46546C67,2,28+len(encoded)+len(blob))+struct.pack("<II",len(encoded),0x4E4F534A)+encoded+struct.pack("<II",len(blob),0x004E4942)+blob
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_bytes(binary)
    stats={"asset":OUT.name,"stage":"original procedural blockout+; no textures or animation clips", "axes":{"up":"+Y","forward":"-Z","units":"metres"},"vertices":sum(len(g["positions"]) for m in meshes for g in m.groups.values()),"triangles":sum(len(g["indices"])//3 for m in meshes for g in m.groups.values()),"materials":len(MATERIALS),"draw_primitives":sum(len(m.groups) for m in meshes),"nodes":[n["name"] for n in doc["nodes"]],"bounds_min":[min(p[i] for p in bounds) for i in range(3)],"bounds_max":[max(p[i] for p in bounds) for i in range(3)],"bytes":len(binary),"sha256":hashlib.sha256(binary).hexdigest()}
    stats["dimensions_m"]=[stats["bounds_max"][i]-stats["bounds_min"][i] for i in range(3)]
    assert stats["triangles"] < 35000
    assert abs(stats["bounds_min"][1]) < 1e-8
    # Check the actual container read back from disk and all buffer spans.
    actual=OUT.read_bytes()
    magic,version,total=struct.unpack_from("<III",actual)
    assert magic==0x46546C67 and version==2 and total==len(actual)
    json_size,json_type=struct.unpack_from("<II",actual,12)
    parsed=json.loads(actual[20:20+json_size])
    assert json_type==0x4E4F534A
    bin_size,bin_type=struct.unpack_from("<II",actual,20+json_size)
    assert bin_type==0x004E4942 and bin_size==parsed["buffers"][0]["byteLength"]
    assert all(v["byteOffset"]+v["byteLength"]<=bin_size for v in parsed["bufferViews"])
    OUT.with_suffix(".stats.json").write_text(json.dumps(stats,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(stats,ensure_ascii=False,indent=2))


if __name__ == "__main__":
    write_glb(build_geometry())
