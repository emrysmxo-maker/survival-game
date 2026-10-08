# Общее для сборки построек и машин в Blender: накопитель геометрии по материалам, UV по мировым осям (1 текстура = tile м),
# боксы/призмы/цилиндры, экспорт в glb. Ось X — длина, Y — глубина, Z — вверх; метры (масштаб игры задаёт Godot).
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix, Euler

TEX = os.environ.get('PROP_TEX', '/tmp/claude-0/props/tex')
_mats = {}

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()

def material(name, tex=None, color=(0.5, 0.5, 0.5, 1), rough=0.9, metal=0.0, tile=1.0, smooth=False):
    key = name
    if key in _mats: return _mats[key]
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    if tex:
        t = m.node_tree.nodes.new('ShaderNodeTexImage')
        ext = 'png' if tex in ('chain', 'net') else 'jpg'
        t.image = bpy.data.images.load(f'{TEX}/{tex}.{ext}'); t.image.colorspace_settings.name = 'sRGB'
        m.node_tree.links.new(t.outputs['Color'], b.inputs['Base Color'])
        if tex in ('chain', 'net'):
            m.node_tree.links.new(t.outputs['Alpha'], b.inputs['Alpha']); m.blend_method = 'BLEND'
    else:
        b.inputs['Base Color'].default_value = color
    m['tile'] = tile
    m['smooth'] = smooth
    _mats[key] = m
    return m

class Acc:
    """накопитель: материал -> bmesh; примитивы кладутся сразу в координатах модели"""
    def __init__(self): self.bms = {}
    def _bm(self, m):
        if m.name not in self.bms: self.bms[m.name] = (m, bmesh.new())
        return self.bms[m.name][1]

    def box(self, m, c, s, rot=(0, 0, 0), pivot=None):
        """c — центр, s — размеры (x,y,z), rot — углы Эйлера (рад) вокруг pivot (по умолчанию — центр)"""
        bm = self._bm(m)
        M = Matrix.Translation(c) @ Euler(rot, 'XYZ').to_matrix().to_4x4() @ Matrix.Diagonal((s[0], s[1], s[2], 1))
        if pivot is not None:
            P = Matrix.Translation(pivot) @ Euler(rot, 'XYZ').to_matrix().to_4x4() @ Matrix.Translation(-Vector(pivot))
            M = P @ (Matrix.Translation(c) @ Matrix.Diagonal((s[0], s[1], s[2], 1)))
        bmesh.ops.create_cube(bm, size=1.0, matrix=M)

    def poly(self, m, pts, vec):
        """выдавить многоугольник pts (3D, по кругу) на вектор vec"""
        bm = self._bm(m)
        a = [bm.verts.new(Vector(p)) for p in pts]
        b = [bm.verts.new(Vector(p) + Vector(vec)) for p in pts]
        n = len(pts)
        bm.faces.new(a); bm.faces.new(b[::-1])
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([a[i], a[j], b[j], b[i]])

    def hexa(self, m, v):
        """выпуклый шестигранник по 8 вершинам: низ (0..3 по кругу), верх (4..7 над ними)"""
        bm = self._bm(m)
        vs = [bm.verts.new(Vector(p)) for p in v]
        for f in ([0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]):
            bm.faces.new([vs[i] for i in f])

    def loft(self, m, rings, cap=True):
        """поверхность по сечениям (кольца точек одинакового числа), замкнутая; концы закрыты"""
        bm = self._bm(m)
        vs = [[bm.verts.new(Vector(p)) for p in ring] for ring in rings]
        n = len(rings[0])
        for i in range(len(rings) - 1):
            for j in range(n):
                k = (j + 1) % n
                try: bm.faces.new([vs[i][j], vs[i][k], vs[i + 1][k], vs[i + 1][j]])
                except ValueError: pass
        if cap:
            try: bm.faces.new(vs[0][::-1])
            except ValueError: pass
            try: bm.faces.new(vs[-1])
            except ValueError: pass

    def quad_xz(self, m, x0, x1, z0, z1, y):
        self.face(m, [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)])

    def face(self, m, pts):
        bm = self._bm(m)
        try: bm.faces.new([bm.verts.new(Vector(p)) for p in pts])
        except ValueError: pass

    def beam(self, m, p0, p1, w=0.08, h=None):
        """брус/шест от точки p0 до p1 сечением w×h"""
        p0 = Vector(p0); p1 = Vector(p1); d = p1 - p0
        if d.length < 1e-6: return
        q = d.normalized().to_track_quat('Z', 'Y')
        M = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((w, h or w, d.length, 1))
        bmesh.ops.create_cube(self._bm(m), size=1.0, matrix=M)

    def torus(self, m, c, R, r, axis='Y', seg=18, sides=8):
        """тор (покрышка): большой радиус R, малый r, ось axis"""
        rings = []
        for i in range(seg + 1):
            t = 2 * math.pi * i / seg
            ring = []
            for j in range(sides):
                u = 2 * math.pi * j / sides
                rr = R + r * math.cos(u)
                p = (rr * math.cos(t), rr * math.sin(t), r * math.sin(u))      # ось тора — Z
                if axis == 'X': p = (p[2], p[1], p[0])
                elif axis == 'Y': p = (p[0], p[2], p[1])
                ring.append((p[0] + c[0], p[1] + c[1], p[2] + c[2]))
            rings.append(ring)
        self.loft(m, rings, cap=False)

    def cyl(self, m, c, r, h, axis='Y', seg=14, r2=None):
        bm = self._bm(m)
        rot = {'X': Euler((0, math.pi / 2, 0)), 'Y': Euler((-math.pi / 2, 0, 0)), 'Z': Euler((0, 0, 0))}[axis]
        M = Matrix.Translation(c) @ rot.to_matrix().to_4x4()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h, matrix=M)

    def build(self, name):
        objs = []
        for mname, (m, bm) in self.bms.items():
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            tile = float(m.get('tile', 1.0))
            uv = bm.loops.layers.uv.verify()
            for f in bm.faces:
                n = f.normal
                ax = max(range(3), key=lambda i: abs(n[i]))
                for l in f.loops:
                    p = l.vert.co
                    u, v = ((p.y, p.z), (p.x, p.z), (p.x, p.y))[ax]
                    l[uv].uv = (u / tile, v / tile)
            me = bpy.data.meshes.new(name + '_' + mname)
            bm.to_mesh(me); bm.free()
            me.materials.append(m)
            sm = bool(m.get('smooth', False))
            for p in me.polygons: p.use_smooth = sm
            o = bpy.data.objects.new(name + '_' + mname, me)
            bpy.context.scene.collection.objects.link(o)
            objs.append(o)
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs: o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        o.name = name
        return o

def export(obj, path):
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_image_format='JPEG', export_jpeg_quality=85, export_apply=True)

def preview(obj, path, views=((1, -1.3, 0.8), (-1, 1.3, 0.8)), res=520, samples=24, fit=1.5):
    """картинка для проверки: Cycles на CPU, 2 ракурса (в одну полосу)"""
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.samples = samples; sc.cycles.device = 'CPU'
    sc.render.resolution_x = res; sc.render.resolution_y = int(res * 0.8)
    w = bpy.data.worlds.new('w'); w.use_nodes = True; w.node_tree.nodes['Background'].inputs[0].default_value = (0.62, 0.7, 0.8, 1)
    w.node_tree.nodes['Background'].inputs[1].default_value = 1.0
    sc.world = w
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35)); bpy.context.scene.collection.objects.link(sun)
    gm = material('_ground', color=(0.28, 0.3, 0.18, 1), rough=1.0)
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    me = bpy.data.meshes.new('g'); bm.to_mesh(me); me.materials.append(gm)
    g = bpy.data.objects.new('g', me); bpy.context.scene.collection.objects.link(g)
    dims = obj.dimensions; r = max(dims) * fit + 1.5
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); bpy.context.scene.collection.objects.link(cam); sc.camera = cam
    cam.data.lens = 40
    outs = []
    for i, v in enumerate(views):
        d = Vector(v).normalized()
        cam.location = Vector((0, 0, dims.z * 0.4)) + d * r
        cam.rotation_euler = (Vector((0, 0, dims.z * 0.4)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = f'{path}_{i}.png'
        bpy.ops.render.render(write_still=True)
        outs.append(sc.render.filepath)
    return outs
