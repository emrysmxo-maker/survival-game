# Реалистичные дома (2027 год, средняя полоса): полые, в настоящий размер (человек 1,8 м), с проёмами,
# комнатами, отделкой внутри; крыша — отдельный объект «<имя>_roof» (прячется, когда герой внутри).
# Фото-текстуры CC0 (Poly Haven, tools/houses/get_tex.py) + карты нормалей; цвет/затенение/грязь — цвет вершин.
# Ось X — вдоль фасада, Y — глубина (фасад смотрит в -Y), Z — вверх. Метры.
#   /tmp/claude-0/blender/v/bin/python -I tools/houses/house.py <out_dir> [ONLY=имена] [SHOW=1]
import bpy, bmesh, math, os, random, sys, zlib
from mathutils import Vector, Matrix, Euler

TEX = os.environ.get("HOUSE_TEX", "/tmp/claude-0/houses/tex")
UP = Vector((0, 0, 1))

# ---------------- материалы ----------------
# имя: (текстура Poly Haven, размер плитки в метрах (ширина, высота), повернуть на 90°, шероховатость)
TEXDEF = {
	"logs": ("wood_trunk_wall", (1.6, 1.6), True, 0.85),
	"planks_blue": ("blue_painted_planks", (2.0, 2.0), False, 0.8),
	"planks_green": ("green_rough_planks", (2.0, 2.0), False, 0.85),
	"planks_brown": ("weathered_plank_siding", (2.0, 2.0), False, 0.85),
	"planks_peel": ("wood_peeling_paint_weathered", (1.6, 1.6), False, 0.85),
	"brick_red": ("brick_wall_02", (1.6, 1.6), False, 0.9),
	"brick_white": ("painted_worn_brick", (1.6, 1.6), False, 0.9),
	"plaster_yellow": ("yellow_plaster", (2.5, 2.5), False, 0.9),
	"plaster_beige": ("beige_wall_001", (2.5, 2.5), False, 0.9),
	"plaster_white": ("white_plaster_rough_01", (2.5, 2.5), False, 0.9),
	"plaster_old": ("worn_mossy_plasterwall", (2.5, 2.5), False, 0.9),
	"block": ("concrete_block_wall", (2.4, 2.4), False, 0.9),
	"slate": ("corrugated_iron", (1.8, 1.8), False, 0.8),
	"tin_rust": ("rusty_corrugated_iron", (1.8, 1.8), False, 0.7),
	"profnastil": ("box_profile_metal_sheet", (2.0, 2.0), False, 0.45),
	"shingle": ("roof_slates_02", (2.0, 2.0), False, 0.85),
	"floor_wood": ("old_wooden_floor_01", (2.0, 2.0), False, 0.8),
	"linoleum": ("old_linoleum_flooring_01", (2.0, 2.0), False, 0.7),
	"wallpaper": ("decrepit_wallpaper", (2.0, 2.0), False, 0.9),
	"paint_wall": ("peeling_painted_wall", (2.0, 2.0), False, 0.9),
	"concrete": ("concrete_wall_006", (2.5, 2.5), False, 0.95),
	"door": ("rough_pine_door", (1.0, 2.1), False, 0.8),
}
FLAT = {   # без текстуры: (цвет sRGB, шероховатость, металл)
	"frame_white": ((0.88, 0.88, 0.86), 0.5, 0.0), "frame_wood": ((0.42, 0.33, 0.24), 0.7, 0.0),
	"glass": ((0.10, 0.13, 0.14), 0.05, 0.0), "dark": ((0.035, 0.03, 0.028), 1.0, 0.0),
	"metal": ((0.55, 0.56, 0.57), 0.4, 1.0), "metal_paint": ((0.72, 0.72, 0.70), 0.5, 0.3),
	"gas": ((0.85, 0.68, 0.10), 0.5, 0.2), "soot": ((0.05, 0.045, 0.04), 1.0, 0.0),
	"stove": ((0.86, 0.85, 0.80), 0.95, 0.0), "wood_raw": ((0.50, 0.40, 0.29), 0.85, 0.0),
	"rubber": ((0.08, 0.08, 0.08), 0.9, 0.0),
	"headlight": ((0.80, 0.82, 0.84), 0.05, 0.6), "frame": ((0.08, 0.08, 0.08), 0.6, 0.4),
}
_MATS = {}

def srgb2lin(c):
	return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def mat(name):
	if name in _MATS:
		return _MATS[name]
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	b = nt.nodes["Principled BSDF"]
	if name in TEXDEF:
		tid, tile, rot, rough = TEXDEF[name]
		t = nt.nodes.new("ShaderNodeTexImage")
		t.image = _img(tid + "_diff.jpg")
		nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
		tn = nt.nodes.new("ShaderNodeTexImage")
		tn.image = _img(tid + "_nor.jpg", True)
		nm = nt.nodes.new("ShaderNodeNormalMap")
		nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
		nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
		b.inputs["Roughness"].default_value = rough
		m["tile"] = tile
		m["rot"] = rot
	else:
		col, rough, metal = FLAT[name]
		b.inputs["Base Color"].default_value = srgb2lin(col) + (1,)
		b.inputs["Roughness"].default_value = rough
		b.inputs["Metallic"].default_value = metal
		m["tile"] = (1.0, 1.0)
		m["rot"] = False
	_MATS[name] = m
	return m

_IMGS = {}
def _img(f, noncolor=False):
	if f not in _IMGS:
		im = bpy.data.images.load(os.path.join(TEX, f))
		if noncolor:
			im.colorspace_settings.name = "Non-Color"
		_IMGS[f] = im
	return _IMGS[f]

# ---------------- накопитель геометрии ----------------
class HB:
	"""Геометрия по материалам; у каждого примитива — цвет (оттенок краски/копоть), UV по мировым осям в метрах."""
	def __init__(s, keep_winding=False):
		s.bms = {}
		s.keep_winding = keep_winding                                  # True — не пересчитывать нормали (кузов машины задан наружу)

	def _bm(s, m):
		if m not in s.bms:
			bm = bmesh.new()
			bm.loops.layers.color.new("Color")
			s.bms[m] = bm
		return s.bms[m]

	def _paint(s, bm, faces, col):
		cl = bm.loops.layers.color["Color"]
		c = tuple(srgb2lin(col)) + (1.0,)
		for f in faces:
			for l in f.loops:
				l[cl] = c

	def box(s, m, c, size, col=(1, 1, 1), rot=(0, 0, 0)):
		bm = s._bm(m)
		M = Matrix.Translation(c) @ Euler(rot, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((size[0], size[1], size[2], 1))
		r = bmesh.ops.create_cube(bm, size=1.0, matrix=M)
		fs = list({f for v in r["verts"] for f in v.link_faces})
		s._paint(bm, fs, col)

	def poly(s, m, pts, vec, col=(1, 1, 1)):
		bm = s._bm(m)
		a = [bm.verts.new(Vector(p)) for p in pts]
		b = [bm.verts.new(Vector(p) + Vector(vec)) for p in pts]
		n = len(pts)
		fs = [bm.faces.new(a), bm.faces.new(b[::-1])]
		for i in range(n):
			j = (i + 1) % n
			fs.append(bm.faces.new([a[i], a[j], b[j], b[i]]))
		s._paint(bm, fs, col)

	def beam(s, m, p0, p1, w=0.08, h=None, col=(1, 1, 1)):
		p0, p1 = Vector(p0), Vector(p1)
		d = p1 - p0
		if d.length < 1e-6:
			return
		q = d.normalized().to_track_quat("Z", "Y")
		M = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((w, h or w, d.length, 1))
		bm = s._bm(m)
		r = bmesh.ops.create_cube(bm, size=1.0, matrix=M)
		s._paint(bm, list({f for v in r["verts"] for f in v.link_faces}), col)

	def cyl(s, m, c, r, h, axis="Z", seg=10, r2=None, col=(1, 1, 1)):
		bm = s._bm(m)
		rot = {"X": Euler((0, math.pi / 2, 0)), "Y": Euler((-math.pi / 2, 0, 0)), "Z": Euler((0, 0, 0))}[axis]
		M = Matrix.Translation(c) @ rot.to_matrix().to_4x4()
		res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h, matrix=M)
		s._paint(bm, list({f for v in res["verts"] for f in v.link_faces}), col)

	def build(s, name, ao=True):
		me = bpy.data.meshes.new(name)
		bm_all = bmesh.new()
		cl_all = bm_all.loops.layers.color.new("Color")
		uv_all = bm_all.loops.layers.uv.new("UVMap")
		mats = list(s.bms.keys())
		for mi, m in enumerate(mats):
			bm = s.bms[m]
			if not s.keep_winding:
				bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
			tw, th = m["tile"]
			rot = bool(m["rot"])
			cl = bm.loops.layers.color["Color"]
			vmap = {}
			for v in bm.verts:
				vmap[v] = bm_all.verts.new(v.co)
			for f in bm.faces:
				try:
					nf = bm_all.faces.new([vmap[v] for v in f.verts])
				except ValueError:
					continue
				nf.material_index = mi
				n = f.normal
				ax = max(range(3), key=lambda i: abs(n[i]))
				for l, nl in zip(f.loops, nf.loops):
					p = l.vert.co
					u, v = ((p.y, p.z), (p.x, p.z), (p.x, p.y))[ax]
					if rot:
						u, v = v, u
					nl[uv_all].uv = (u / tw, v / th)
					c = Vector(l[cl][:3])
					if ao:
						z = p.z
						k = 0.62 + 0.38 * min(1.0, max(0.0, (z - 0.05) / 0.9))   # грязь и затенение у земли
						c = c * k
					nl[cl_all] = (c.x, c.y, c.z, 1.0)
			bm.free()
		bm_all.to_mesh(me)
		bm_all.free()
		for m in mats:
			me.materials.append(m)
		for p in me.polygons:
			p.use_smooth = False
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		me.color_attributes.active_color = me.color_attributes["Color"]
		s.bms = {}
		return ob

	def tris(s):
		return sum(len(f.verts) - 2 for bm in s.bms.values() for f in bm.faces)

# ---------------- части дома ----------------
def wall_x(hb, m, x0, x1, y, t, z0, h, ops, col, side=-1):
	"""Стена вдоль X от x0 до x1, наружная грань на y (side=-1 — фасад смотрит в -Y), толщина t внутрь.
	ops — проёмы [(xc, w, zb, zt)] (zb, zt — от низа стены). Строится простенками, перемычками, подоконной частью."""
	yc = y - side * t / 2
	ops = sorted(ops)
	xs = x0
	for (xc, w, zb, zt) in ops:
		a, b = xc - w / 2, xc + w / 2
		if a - xs > 0.01:
			hb.box(m, ((xs + a) / 2, yc, z0 + h / 2), (a - xs, t, h), col)
		if zb > 0.01:
			hb.box(m, (xc, yc, z0 + zb / 2), (w, t, zb), col)
		if h - zt > 0.01:
			hb.box(m, (xc, yc, z0 + (zt + h) / 2), (w, t, h - zt), col)
		xs = b
	if x1 - xs > 0.01:
		hb.box(m, ((xs + x1) / 2, yc, z0 + h / 2), (x1 - xs, t, h), col)

def wall_y(hb, m, y0, y1, x, t, z0, h, ops, col, side=-1):
	"""То же вдоль Y (боковые стены), наружная грань на x."""
	xc_ = x - side * t / 2
	ops = sorted(ops)
	ys = y0
	for (yc, w, zb, zt) in ops:
		a, b = yc - w / 2, yc + w / 2
		if a - ys > 0.01:
			hb.box(m, (xc_, (ys + a) / 2, z0 + h / 2), (t, a - ys, h), col)
		if zb > 0.01:
			hb.box(m, (xc_, yc, z0 + zb / 2), (t, w, zb), col)
		if h - zt > 0.01:
			hb.box(m, (xc_, yc, z0 + (zt + h) / 2), (t, w, h - zt), col)
		ys = b
	if y1 - ys > 0.01:
		hb.box(m, (xc_, (ys + y1) / 2, z0 + h / 2), (t, y1 - ys, h), col)

def window(hb, S, p, axis, outward, w, h, rnd, kind):
	"""Окно в проёме: p — центр проёма на наружной грани, axis — 'x' (стена вдоль X) или 'y', outward — наружу (+1/-1 по нормали).
	S — стиль: frame (материал рамы), platband (наличники), state: ok/broken/boarded."""
	fm = S["frame"]
	ft = 0.06
	nrm = Vector((0, outward, 0)) if axis == "x" else Vector((outward, 0, 0))
	tan = Vector((1, 0, 0)) if axis == "x" else Vector((0, 1, 0))
	inset = -nrm * 0.12                                               # рама утоплена в проёме
	c = Vector(p) + inset
	def piece(off_t, off_z, sw, sh, depth=0.07, m=fm, col=(1, 1, 1)):
		q = c + tan * off_t + UP * off_z
		size = (sw, depth, sh) if axis == "x" else (depth, sw, sh)
		hb.box(m, tuple(q), size, col)
	# рама
	piece(-w / 2 + ft / 2, 0, ft, h); piece(w / 2 - ft / 2, 0, ft, h)
	piece(0, -h / 2 + ft / 2, w, ft); piece(0, h / 2 - ft / 2, w, ft)
	st = S.get("state", "ok")
	if S.get("pvc"):
		piece(0, 0, ft * 0.8, h)                                      # импост
	else:
		piece(0, 0, ft * 0.8, h); piece(-w / 4, h * 0.2, w / 2, ft * 0.7)   # переплёт «крестом»
	glass = st == "ok" or (st == "broken" and rnd.random() < 0.45)
	if glass:
		piece(0, 0, w - ft, h - ft, 0.012, mat("glass"))              # иначе стекла нет — через проём видна комната
	# отлив/подоконник снаружи
	so = Vector(p) + nrm * 0.06 + UP * (-h / 2 - 0.03)
	hb.box(mat("metal_paint") if S.get("pvc") else fm, tuple(so), (w + 0.1, 0.16, 0.03) if axis == "x" else (0.16, w + 0.1, 0.03))
	if S.get("platband"):                                             # резные наличники избы
		pc = S.get("platcol", (0.9, 0.9, 0.88))
		pm = mat("frame_white")
		q0 = Vector(p) + nrm * 0.025
		for sgn in (-1, 1):
			q = q0 + tan * sgn * (w / 2 + 0.06) + UP * 0.0
			hb.box(pm, tuple(q), (0.12, 0.05, h + 0.25) if axis == "x" else (0.05, 0.12, h + 0.25), pc)
		q = q0 + UP * (h / 2 + 0.14)
		hb.box(pm, tuple(q), (w + 0.36, 0.05, 0.16) if axis == "x" else (0.05, w + 0.36, 0.16), pc)
		q = q0 + UP * (h / 2 + 0.3)                                   # «кокошник»
		hb.box(pm, tuple(q), (w * 0.7, 0.05, 0.14) if axis == "x" else (0.05, w * 0.7, 0.14), pc)
		q = q0 + UP * (-h / 2 - 0.12)
		hb.box(pm, tuple(q), (w + 0.3, 0.05, 0.12) if axis == "x" else (0.05, w + 0.3, 0.12), pc)
		if S.get("shutters"):
			for sgn in (-1, 1):
				q = q0 + nrm * 0.02 + tan * sgn * (w / 2 + 0.06 + w / 4)
				ang = rnd.uniform(-0.25, 0.25)
				hb.box(mat("planks_blue"), tuple(q), (w / 2, 0.04, h) if axis == "x" else (0.04, w / 2, h), S.get("shutcol", (1, 1, 1)))
	if st == "boarded" or (st == "broken" and rnd.random() < 0.3):    # заколочено досками
		for i in range(3):
			q = Vector(p) + nrm * 0.04 + UP * ((i - 1) * h * 0.3)
			rot = (0, rnd.uniform(-0.15, 0.15), 0) if axis == "x" else (rnd.uniform(-0.15, 0.15), 0, 0)
			hb.box(mat("wood_raw"), tuple(q), (w + 0.3, 0.03, 0.14) if axis == "x" else (0.03, w + 0.3, 0.14), (0.85, 0.85, 0.85), rot)

def door(hb, p, axis, outward, w, h, rnd, open_k=0.0, kind="wood"):
	nrm = Vector((0, outward, 0)) if axis == "x" else Vector((outward, 0, 0))
	tan = Vector((1, 0, 0)) if axis == "x" else Vector((0, 1, 0))
	c = Vector(p) - nrm * 0.08
	fm = mat("frame_wood")
	for sgn in (-1, 1):
		q = c + tan * sgn * (w / 2 - 0.04)
		hb.box(fm, tuple(q), (0.08, 0.1, h) if axis == "x" else (0.1, 0.08, h))
	q = c + UP * (h / 2 - 0.04)
	hb.box(fm, tuple(q), (w, 0.1, 0.08) if axis == "x" else (0.1, w, 0.08))
	if open_k < 0:
		return                                                        # двери нет (сорвана)
	# полотно: поворот вокруг петли
	ang = open_k * math.radians(80)                                   # открывается внутрь
	hinge = c + tan * (-w / 2 + 0.06)
	leaf_w = w - 0.12
	dv = tan * math.cos(ang) - nrm * math.sin(ang)
	mid = hinge + dv * leaf_w / 2
	m = mat("door") if kind == "wood" else mat("metal_paint")
	col = (1, 1, 1) if kind == "wood" else (0.45, 0.3, 0.22)
	hb.box(m, tuple(mid), (leaf_w, 0.045, h - 0.1), col, rot=(0, 0, math.atan2(dv.y, dv.x)))

def gable_roof(hb, R, x0, x1, y0, y1, ze, rise, m, col, ov=0.45, th=0.05, holes=None, rnd=None, fascia=True):
	"""Двускатная крыша, конёк вдоль X. Скаты — полосами вдоль ската (можно выкинуть часть — дыры)."""
	yc = (y0 + y1) / 2
	hw = (y1 - y0) / 2 + ov
	X0, X1 = x0 - ov, x1 + ov
	n = max(2, int((X1 - X0) / 0.9))
	for side in (-1, 1):
		for i in range(n):
			if holes and (side, i) in holes:
				continue
			xa = X0 + (X1 - X0) * i / n
			xb = X0 + (X1 - X0) * (i + 1) / n
			pts = [(xa, yc + side * hw, ze - ov * rise / ((y1 - y0) / 2)), (xb, yc + side * hw, ze - ov * rise / ((y1 - y0) / 2)), (xb, yc, ze + rise), (xa, yc, ze + rise)]
			hb.poly(m, pts, (0, 0, th), col)
	# конёк
	hb.beam(R["ridge"], (X0, yc, ze + rise + th), (X1, yc, ze + rise + th), 0.18, 0.08, R.get("ridgecol", col))
	if fascia:
		for side in (-1, 1):
			z = ze - ov * rise / ((y1 - y0) / 2) - 0.08
			hb.beam(mat("frame_wood"), (X0, yc + side * hw, z), (X1, yc + side * hw, z), 0.04, 0.18, R.get("fasciacol", (1, 1, 1)))

def hip_roof(hb, R, x0, x1, y0, y1, ze, rise, m, col, ov=0.5, th=0.05):
	"""Четырёхскатная (вальмовая) крыша."""
	X0, X1, Y0, Y1 = x0 - ov, x1 + ov, y0 - ov, y1 + ov
	dz = ov * rise / ((y1 - y0) / 2)
	zl = ze - dz
	yc = (Y0 + Y1) / 2
	half = (Y1 - Y0) / 2
	ra, rb = X0 + half, X1 - half
	if rb < ra:
		ra = rb = (X0 + X1) / 2
	top = ze + rise
	hb.poly(m, [(X0, Y0, zl), (X1, Y0, zl), (rb, yc, top), (ra, yc, top)], (0, 0, th), col)
	hb.poly(m, [(X1, Y1, zl), (X0, Y1, zl), (ra, yc, top), (rb, yc, top)], (0, 0, th), col)
	hb.poly(m, [(X0, Y1, zl), (X0, Y0, zl), (ra, yc, top)], (0, 0, th), col)
	hb.poly(m, [(X1, Y0, zl), (X1, Y1, zl), (rb, yc, top)], (0, 0, th), col)
	if rb > ra:
		hb.beam(R["ridge"], (ra, yc, top + th), (rb, yc, top + th), 0.18, 0.08, R.get("ridgecol", col))
	for (a, b) in (((X0, Y0), (X1, Y0)), ((X1, Y1), (X0, Y1))):
		hb.cyl(mat("metal_paint"), ((a[0] + b[0]) / 2, a[1] + (0.06 if a[1] < 0 else -0.06) * -1, zl - 0.06), 0.06, abs(b[0] - a[0]), "X", 8, col=R.get("guttercol", (0.6, 0.6, 0.6)))

# ---------------- дом целиком ----------------
def house(name, spec, seed):
	"""spec: L, D, wall (материал), wcol, t, h, plinth, roof ('gable'/'hip'), rmat, rcol, pitch, floor, inner,
	front/back/left/right — окна [(pos, w, h)], door (pos, w), porch, chimney (x, y), stove, rooms [перегородки], extras."""
	rnd = random.Random(seed)
	S = spec
	L, D = S["L"], S["D"]
	t = S.get("t", 0.3)
	h = S.get("h", 2.7)
	zp = S.get("plinth", 0.5)
	floors = S.get("floors", 1)
	slab = 0.3
	H = h * floors + slab * (floors - 1)
	wm, wc = mat(S["wall"]), S.get("wcol", (1, 1, 1))
	im, ic = mat(S.get("inner", "wallpaper")), S.get("icol", (1, 1, 1))
	hb = HB()
	x0, x1, y0, y1 = -L / 2, L / 2, -D / 2, D / 2
	# фундамент/цоколь
	hb.box(mat(S.get("plinth_mat", "concrete")), (0, 0, zp / 2 - 0.15), (L + 0.12, D + 0.12, zp + 0.3), S.get("pcol", (0.9, 0.9, 0.9)))
	style = {"frame": mat(S.get("frame", "frame_wood")), "pvc": S.get("pvc", False), "platband": S.get("platband", False),
		"platcol": S.get("platcol", (0.9, 0.9, 0.88)), "state": S.get("state", "ok"), "shutters": S.get("shutters", False), "shutcol": S.get("shutcol", (1, 1, 1))}
	wh, ww = S.get("win_h", 1.4), S.get("win_w", 1.2)
	sill = S.get("sill", 0.85)
	dpos, dw = S.get("door", (-L / 2 + 1.4, 0.95))
	for fl in range(floors):
		z0 = zp + fl * (h + slab)
		def ops_for(lst, with_door=False):
			o = [(pp, w2 or ww, sill, sill + (h2 or wh)) for (pp, w2, h2) in lst]
			if with_door and fl == 0:
				o.append((dpos, dw, 0.0, 2.1))
			return o
		front = ops_for(S.get("front", []), True)
		back = ops_for(S.get("back", []))
		left = ops_for(S.get("left", []))
		right = ops_for(S.get("right", []))
		if fl > 0:
			front = ops_for(S.get("front2", S.get("front", [])))
		# наружные стены (у нижних этажей — на толщину перекрытия выше) и внутренняя отделка
		hx = h + (slab if fl < floors - 1 else 0.0)
		wall_x(hb, wm, x0, x1, y0, t, z0, hx, front, wc, -1)
		wall_x(hb, wm, x0, x1, y1, t, z0, hx, back, wc, +1)
		wall_y(hb, wm, y0 + t, y1 - t, x0, t, z0, hx, left, wc, -1)
		wall_y(hb, wm, y0 + t, y1 - t, x1, t, z0, hx, right, wc, +1)
		if S.get("lining", True):
			lt = 0.02
			wall_x(hb, im, x0 + t, x1 - t, y0 + t + lt, lt, z0, h, front, ic, -1)
			wall_x(hb, im, x0 + t, x1 - t, y1 - t - lt, lt, z0, h, back, ic, +1)
			wall_y(hb, im, y0 + t, y1 - t, x0 + t + lt, lt, z0, h, left, ic, -1)
			wall_y(hb, im, y0 + t, y1 - t, x1 - t - lt, lt, z0, h, right, ic, +1)
		# пол этажа
		hb.box(mat(S.get("floor", "floor_wood")), (0, 0, z0 + 0.02), (L - 2 * t, D - 2 * t, 0.04), S.get("fcol", (1, 1, 1)))
		# перегородки с дверными проёмами
		for (ax, pos, a, b, dp) in S.get("rooms", []):
			if ax == "x":                                              # перегородка вдоль X на y=pos от x=a до x=b, дверь в dp
				wall_x(hb, im, a, b, pos + 0.06, 0.12, z0, h, [(dp, 0.85, 0.0, 2.05)] if dp is not None else [], ic, -1)
			else:
				wall_y(hb, im, a, b, pos + 0.06, 0.12, z0, h, [(dp, 0.85, 0.0, 2.05)] if dp is not None else [], ic, -1)
		# окна
		for (side, lst) in (("f", front), ("b", back), ("l", left), ("r", right)):
			for (pp, w2, zb, zt) in lst:
				if zb < 0.01:
					continue                                           # дверь
				hh = zt - zb
				if side == "f":
					window(hb, style, (pp, y0, z0 + zb + hh / 2), "x", -1, w2, hh, rnd, 0)
				elif side == "b":
					window(hb, style, (pp, y1, z0 + zb + hh / 2), "x", 1, w2, hh, rnd, 0)
				elif side == "l":
					window(hb, style, (x0, pp, z0 + zb + hh / 2), "y", -1, w2, hh, rnd, 0)
				else:
					window(hb, style, (x1, pp, z0 + zb + hh / 2), "y", 1, w2, hh, rnd, 0)
		if fl < floors - 1:                                           # перекрытие между этажами (с проёмом под лестницу)
			hb.box(mat("concrete"), (L / 4, 0, z0 + h + slab / 2), (L / 2 - t, D - 2 * t, slab), (0.8, 0.8, 0.8))
			hb.box(mat("concrete"), (-L / 4 - 0.6, 0, z0 + h + slab / 2), (L / 2 - t - 1.2, D - 2 * t, slab), (0.8, 0.8, 0.8))
			for i in range(14):                                       # лестница
				zz = z0 + (i + 0.5) * (h + slab) / 14
				hb.box(mat("floor_wood"), (-1.0 + 0.0, y0 + t + 0.5 + i * 0.25, zz), (0.95, 0.27, 0.05))
	# дверь
	door(hb, (dpos, y0, zp + 1.05), "x", -1, dw, 2.1, rnd, S.get("door_open", rnd.uniform(0, 0.6)), S.get("door_kind", "wood"))
	# крыльцо
	por = S.get("porch")
	if por:
		pw, pd = por.get("w", 1.8), por.get("d", 1.3)
		pm, pcl = mat(por.get("mat", "floor_wood")), por.get("col", (0.9, 0.9, 0.9))
		hb.box(pm, (dpos, y0 - pd / 2, zp / 2), (pw, pd, zp), pcl)            # площадка
		n = max(1, round(zp / 0.17))
		for k in range(1, n):                                          # ступени
			hz = zp * (n - k) / n
			hb.box(pm, (dpos, y0 - pd - (k - 0.5) * 0.3, hz / 2), (pw * 0.8, 0.3, hz), pcl)
		if por.get("roof"):
			for sx in (-1, 1):
				hb.box(mat("frame_wood"), (dpos + sx * (pw / 2 - 0.08), y0 - pd + 0.1, zp + 1.25), (0.1, 0.1, 2.5))
			hb.box(mat(S["rmat"]), (dpos, y0 - pd / 2 - 0.05, zp + 2.6), (pw + 0.3, pd + 0.4, 0.04), S["rcol"], rot=(0.2, 0, 0))
	# печь (изба) / котёл
	if S.get("stove"):
		sx, sy = S["stove"]
		hb.box(mat("stove"), (sx, sy, zp + 0.9), (1.6, 2.0, 1.8), (0.95, 0.93, 0.88))
		hb.box(mat("soot"), (sx, sy - 1.0, zp + 0.95), (0.5, 0.04, 0.4))
	# отделка: внешние мелочи
	ex = S.get("extras", [])
	zt = zp + H
	if "gas" in ex:                                                   # газовая труба по фасаду
		hb.cyl(mat("gas"), (0, y0 - 0.12, zp + 2.0), 0.03, L - 0.6, "X", 6)
		hb.cyl(mat("gas"), (x1 - 0.3, y0 - 0.12, zp + 1.0), 0.03, 2.0, "Z", 6)
	if "ac" in ex:
		hb.box(mat("metal_paint"), (x1 - 1.6, y0 - 0.2, zp + 2.1), (0.8, 0.3, 0.55), (0.95, 0.95, 0.95))
	if "dish" in ex:
		hb.cyl(mat("metal_paint"), (x0 + 1.2, y0 - 0.35, zt - 0.5), 0.3, 0.06, "Y", 12, col=(0.9, 0.9, 0.9))
		hb.beam(mat("metal"), (x0 + 1.2, y0 - 0.02, zt - 0.5), (x0 + 1.2, y0 - 0.35, zt - 0.5), 0.03)
	if "downpipe" in ex:
		for xx in (x0 + 0.15, x1 - 0.15):
			hb.cyl(mat("metal_paint"), (xx, y0 - 0.12, (zt - 0.1) / 2), 0.05, zt - 0.1, "Z", 8, col=S.get("guttercol", (0.6, 0.6, 0.6)))
	shell = hb.build(name)
	# ---- крыша (отдельный объект) ----
	rb = HB()
	pitch = math.radians(S.get("pitch", 32))
	rise = (D / 2) * math.tan(pitch)
	R = {"ridge": mat(S["rmat"]) if S["rmat"] != "slate" else mat("metal_paint"), "ridgecol": S.get("ridgecol", S["rcol"]), "guttercol": S.get("guttercol", (0.6, 0.6, 0.6))}
	# потолок (часть крыши: прячется вместе с ней)
	rb.box(mat(S.get("ceil", "paint_wall")), (0, 0, zt + 0.02), (L - 2 * t, D - 2 * t, 0.04), (0.92, 0.9, 0.86))
	holes = None
	if S.get("state") in ("ruin",):
		holes = {(rnd.choice((-1, 1)), rnd.randrange(2, 6)) for _ in range(3)}
	if S.get("roof", "gable") == "gable":
		gable_roof(rb, R, x0, x1, y0, y1, zt, rise, mat(S["rmat"]), S["rcol"], S.get("ov", 0.45), holes=holes, rnd=rnd)
		gm = mat(S.get("gable_mat", S["wall"]))                     # фронтоны
		for sx in (-1, 1):
			xx = (x0 + t / 2) if sx < 0 else (x1 - t / 2)
			rb.poly(gm, [(xx - t / 2, y0, zt), (xx - t / 2, y1, zt), (xx - t / 2, 0, zt + rise)], (t, 0, 0), S.get("gcol", wc))
	else:
		hip_roof(rb, R, x0, x1, y0, y1, zt, rise, mat(S["rmat"]), S["rcol"], S.get("ov", 0.5))
	ch = S.get("chimney")
	if ch:
		cx, cy = ch
		rb.box(mat(S.get("chim_mat", "brick_red")), (cx, cy, zt + rise * 0.7 + 0.5), (0.55, 0.55, rise * 1.0 + 1.0), S.get("chimcol", (1, 1, 1)))
		rb.box(mat("concrete"), (cx, cy, zt + rise * 1.2 + 1.02), (0.7, 0.7, 0.08), (0.7, 0.7, 0.7))
	if "antenna" in ex:
		ax_ = x0 + L * 0.3
		rb.beam(mat("metal"), (ax_, 0, zt + rise), (ax_, 0, zt + rise + 2.2), 0.04)
		for i in range(4):
			rb.beam(mat("metal"), (ax_ - 0.5 + i * 0.05, -0.0, zt + rise + 1.4 + i * 0.22), (ax_ + 0.5 - i * 0.05, 0, zt + rise + 1.4 + i * 0.22), 0.02)
	roof = rb.build(name + "_roof", ao=False)
	return shell, roof

# ---------------- типы домов ----------------
def W(*xs, w=None, h=None):
	return [(x, w, h) for x in xs]

TYPES = {
	# изба-пятистенок: бревно, шифер, резные наличники, русская печь
	"house_izba_a": dict(L=8.0, D=6.6, wall="logs", t=0.24, h=2.5, plinth=0.6, plinth_mat="brick_red", pcol=(0.8, 0.8, 0.8),
		roof="gable", rmat="slate", rcol=(0.80, 0.76, 0.70), pitch=34, inner="wallpaper", floor="floor_wood",
		front=W(-0.6, 1.4, 3.1, w=1.0, h=1.3), back=W(-2.0, 1.5, w=1.0, h=1.3), left=W(0.0, w=1.0, h=1.3), right=W(-1.2, 1.4, w=1.0, h=1.3),
		door=(-2.9, 0.9), porch=dict(w=1.6, d=1.4, roof=True), chimney=(0.8, 0.6), stove=(0.8, 0.6),
		rooms=[("y", -1.9, -3.0, 3.0, 1.6)], platband=True, platcol=(0.88, 0.9, 0.9), shutters=True, shutcol=(0.55, 0.75, 0.95), state="broken", extras=["antenna"]),
	"house_izba_b": dict(L=7.2, D=6.2, wall="logs", t=0.24, h=2.4, plinth=0.55, plinth_mat="concrete", roof="gable", rmat="profnastil", rcol=(0.38, 0.75, 0.50), pitch=30,
		inner="paint_wall", icol=(0.8, 0.9, 0.85), floor="floor_wood", front=W(-0.4, 1.5, 2.8, w=1.0, h=1.3), back=W(0.5, w=1.0, h=1.3), left=W(0.5, w=1.0, h=1.2), right=W(-1.0, 1.2, w=1.0, h=1.3),
		door=(-2.5, 0.9), porch=dict(w=1.5, d=1.2, roof=False), chimney=(0.4, 0.5), stove=(0.4, 0.5), rooms=[("y", -1.6, -2.8, 2.8, 1.2)],
		platband=True, platcol=(0.55, 0.78, 0.55), state="boarded"),
	"house_izba_c": dict(L=7.6, D=6.4, wall="planks_blue", wcol=(0.95, 1.0, 1.0), t=0.22, h=2.5, plinth=0.6, roof="gable", rmat="slate", rcol=(0.78, 0.74, 0.68), pitch=33,
		inner="wallpaper", front=W(-0.5, 1.3, 2.9, w=1.0, h=1.3), back=W(-1.5, 1.5, w=1.0, h=1.3), left=W(0.0, w=1.0, h=1.3), right=W(-1.0, 1.2, w=1.0, h=1.3),
		door=(-2.6, 0.9), porch=dict(w=1.6, d=1.3, roof=True), chimney=(0.6, 0.6), stove=(0.6, 0.6), rooms=[("y", -1.7, -2.9, 2.9, 1.5)],
		platband=True, platcol=(0.92, 0.92, 0.9), state="broken", extras=["antenna"]),
	# кирпичный дом 70–80-х: красный кирпич, вальма, шифер
	"house_brick": dict(L=10.0, D=8.4, wall="brick_red", wcol=(1.0, 0.82, 0.74), t=0.4, h=2.7, plinth=0.6, plinth_mat="concrete", roof="hip", rmat="slate", rcol=(0.80, 0.76, 0.70), pitch=27,
		inner="wallpaper", floor="linoleum", front=W(-2.8, -0.6, 1.6, 3.6, w=1.4, h=1.45), back=W(-3.0, 0.0, 3.0, w=1.4, h=1.45), left=W(-1.8, 1.8, w=1.4, h=1.45), right=W(-1.6, 1.8, w=1.4, h=1.45),
		door=(-4.2, 0.95), porch=dict(w=1.8, d=1.4, roof=True, mat="concrete"), chimney=(1.5, 0.8), frame="frame_white",
		rooms=[("x", 0.4, -4.6, 4.6, -3.0), ("y", -1.2, -3.8, 0.4, -1.0), ("y", 2.2, 0.4, 3.8, 1.5)], state="broken", extras=["gas", "dish", "downpipe"]),
	"house_brick_small": dict(L=8.0, D=7.0, wall="brick_white", t=0.38, h=2.6, plinth=0.5, roof="gable", rmat="slate", rcol=(0.80, 0.76, 0.70), pitch=30,
		inner="wallpaper", floor="linoleum", front=W(-1.6, 1.0, 2.8, w=1.3, h=1.4), back=W(-2.0, 1.6, w=1.3, h=1.4), left=W(0.0, w=1.3, h=1.4), right=W(-1.2, 1.4, w=1.3, h=1.4),
		door=(-3.0, 0.95), porch=dict(w=1.6, d=1.3, roof=True, mat="concrete"), chimney=(0.6, 0.5), frame="frame_white", gable_mat="planks_brown",
		rooms=[("y", -1.0, -3.2, 3.2, 1.0)], state="broken", extras=["gas", "downpipe"]),
	# новые дома (2010–2026): газоблок под штукатуркой, пластиковые окна, профнастил/металлочерепица
	"house_new_a": dict(L=10.0, D=9.0, wall="plaster_beige", t=0.4, h=2.8, plinth=0.5, plinth_mat="concrete", pcol=(0.55, 0.52, 0.5), roof="hip", rmat="profnastil", rcol=(0.62, 0.48, 0.40), pitch=25,
		inner="paint_wall", icol=(0.95, 0.95, 0.92), floor="linoleum", front=W(-2.5, 0.0, 2.5, w=1.5, h=1.5), back=W(-3.0, 0.5, 3.0, w=1.5, h=1.5), left=W(-2.0, 2.0, w=1.5, h=1.5), right=W(-2.0, 2.0, w=1.5, h=1.5),
		door=(-4.0, 1.0), door_kind="metal", porch=dict(w=2.2, d=1.6, roof=True, mat="concrete"), chimney=(2.0, 1.0), chim_mat="concrete", pvc=True, frame="frame_white",
		rooms=[("x", 0.6, -4.6, 4.6, -2.5), ("y", -1.0, -4.1, 0.6, -2.0), ("y", 1.8, 0.6, 4.1, 2.0)], state="ok", extras=["gas", "ac", "dish", "downpipe"], ridgecol=(0.62, 0.48, 0.40), guttercol=(0.45, 0.30, 0.24)),
	"house_new_b": dict(L=9.0, D=8.0, wall="planks_brown", t=0.25, h=2.7, plinth=0.6, plinth_mat="concrete", roof="gable", rmat="profnastil", rcol=(0.35, 0.65, 0.45), pitch=30,
		inner="paint_wall", icol=(0.95, 0.92, 0.85), floor="floor_wood", front=W(-1.8, 0.6, 2.8, w=1.4, h=1.5), back=W(-2.0, 1.8, w=1.4, h=1.5), left=W(0.0, w=1.4, h=1.5), right=W(-1.5, 1.5, w=1.4, h=1.5),
		door=(-3.4, 1.0), door_kind="metal", porch=dict(w=2.4, d=1.8, roof=True), chimney=(1.0, 0.8), chim_mat="brick_red", pvc=True, frame="frame_white",
		rooms=[("y", -0.5, -3.75, 3.75, 1.5)], state="ok", extras=["ac", "dish", "downpipe"], gable_mat="planks_brown"),
	# коттедж: 2 этажа, белая штукатурка, металлочерепица
	"house_cottage": dict(L=10.0, D=10.0, wall="plaster_white", t=0.4, h=2.8, floors=2, plinth=0.6, plinth_mat="concrete", pcol=(0.5, 0.48, 0.46), roof="hip", rmat="profnastil", rcol=(0.85, 0.55, 0.50), pitch=28,
		inner="paint_wall", floor="linoleum", front=W(-3.0, 0.0, 3.0, w=1.5, h=1.6), front2=W(-3.0, 0.0, 3.0, w=1.5, h=1.6), back=W(-3.0, 0.0, 3.0, w=1.5, h=1.6), left=W(-2.5, 2.5, w=1.5, h=1.6), right=W(-2.5, 2.5, w=1.5, h=1.6),
		door=(-1.5, 1.1), door_kind="metal", porch=dict(w=3.0, d=2.0, roof=True, mat="concrete"), chimney=(2.5, 1.5), chim_mat="brick_red", pvc=True, frame="frame_white",
		rooms=[("x", 0.8, -4.6, 4.6, 2.5)], state="ok", extras=["gas", "ac", "dish", "downpipe"], ridgecol=(0.85, 0.55, 0.50), guttercol=(0.45, 0.22, 0.18)),
	# дачи: щитовые домики, вагонка
	"house_dacha_a": dict(L=6.0, D=5.0, wall="planks_green", t=0.16, h=2.4, plinth=0.45, plinth_mat="concrete", roof="gable", rmat="profnastil", rcol=(0.36, 0.70, 0.42), pitch=34,
		inner="paint_wall", front=W(0.4, 1.9, w=1.1, h=1.2), back=W(-1.2, 1.2, w=1.0, h=1.2), left=W(0.0, w=1.0, h=1.2), right=W(0.0, w=1.0, h=1.2),
		door=(-1.6, 0.85), porch=dict(w=2.6, d=1.6, roof=True), chimney=(1.0, 0.4), stove=None, rooms=[("y", -0.2, -2.35, 2.35, 1.0)], state="broken"),
	"house_dacha_b": dict(L=6.4, D=5.2, wall="planks_blue", t=0.16, h=2.4, plinth=0.45, roof="gable", rmat="profnastil", rcol=(1.0, 0.85, 0.80), pitch=36,
		inner="wallpaper", front=W(0.6, 2.1, w=1.1, h=1.2), back=W(-1.4, 1.2, w=1.0, h=1.2), left=W(0.0, w=1.0, h=1.2), right=W(0.4, w=1.0, h=1.2),
		door=(-1.7, 0.85), porch=dict(w=2.4, d=1.5, roof=True), chimney=(1.2, 0.5), rooms=[("y", -0.4, -2.45, 2.45, 1.2)], state="boarded"),
	"house_dacha_c": dict(L=5.6, D=5.0, wall="planks_peel", t=0.16, h=2.3, plinth=0.4, roof="gable", rmat="tin_rust", rcol=(0.9, 0.9, 0.9), pitch=32,
		inner="paint_wall", front=W(0.8, w=1.1, h=1.2), back=W(0.0, w=1.0, h=1.2), left=W(0.0, w=1.0, h=1.2), right=W(0.0, w=1.0, h=1.2),
		door=(-1.2, 0.85), porch=dict(w=1.6, d=1.2, roof=False), chimney=(1.0, 0.4), state="ruin"),
	"house_dacha_d": dict(L=6.0, D=5.4, wall="planks_brown", t=0.18, h=2.4, plinth=0.45, roof="gable", rmat="slate", rcol=(0.78, 0.74, 0.68), pitch=34,
		inner="wallpaper", front=W(0.5, 2.0, w=1.1, h=1.2), back=W(-1.3, 1.3, w=1.0, h=1.2), left=W(0.0, w=1.0, h=1.2), right=W(0.0, w=1.0, h=1.2),
		door=(-1.6, 0.85), porch=dict(w=2.0, d=1.4, roof=True), chimney=(1.0, 0.5), rooms=[("y", -0.2, -2.5, 2.5, 1.0)], state="broken", extras=["antenna"]),
	# лесная изба, баня
	"house_cabin": dict(L=6.0, D=5.0, wall="logs", t=0.24, h=2.3, plinth=0.5, plinth_mat="concrete", roof="gable", rmat="tin_rust", rcol=(0.9, 0.9, 0.9), pitch=32,
		inner="paint_wall", icol=(0.7, 0.62, 0.5), front=W(0.8, w=0.9, h=1.0), back=W(0.0, w=0.9, h=1.0), left=W(0.0, w=0.8, h=1.0), right=W(0.0, w=0.8, h=1.0),
		door=(-1.5, 0.85), porch=dict(w=1.4, d=1.1, roof=True), chimney=(0.8, 0.6), stove=(0.9, 0.9), state="broken"),
	"house_banya": dict(L=4.6, D=4.0, wall="logs", t=0.22, h=2.2, plinth=0.4, plinth_mat="concrete", roof="gable", rmat="slate", rcol=(0.78, 0.74, 0.68), pitch=30,
		inner="paint_wall", icol=(0.7, 0.6, 0.48), floor="floor_wood", lining=False, front=[], back=W(0.6, w=0.6, h=0.5), left=[], right=W(0.0, w=0.6, h=0.5),
		door=(-1.2, 0.8), chimney=(0.9, 0.6), stove=(1.1, 0.8), rooms=[("y", -0.4, -1.75, 1.75, 0.0)], state="ok"),
}

# ---------------- заборы и площадки ----------------
def fence_prof(name, col):
	"""Секция забора из профнастила: 2,5 м, высота 1,9 м, металлические столбы и прожилины."""
	hb = HB()
	L = 2.5
	for x in (-L / 2, L / 2):
		hb.box(mat("metal_paint"), (x, 0, 1.0), (0.06, 0.06, 2.1), (0.25, 0.25, 0.25))
	for z in (0.45, 1.55):
		hb.box(mat("metal_paint"), (0, 0.05, z), (L, 0.04, 0.04), (0.3, 0.3, 0.3))
	hb.box(mat("profnastil"), (0, -0.0, 1.0), (L - 0.02, 0.025, 1.9), col)
	o = hb.build(name)
	return o, None

def fence_mil(name, broken):
	"""Военный забор: бетонные столбы 2,8 м, сетка 2,5 м, сверху козырёк с колючей проволокой."""
	hb = HB()
	L = 3.0
	for x in (-L / 2, L / 2):
		hb.box(mat("concrete"), (x, 0, 1.4), (0.16, 0.16, 2.8), (0.85, 0.85, 0.85))
		hb.beam(mat("metal"), (x, 0, 2.8), (x, -0.45, 3.2), 0.05)
	for z in (0.1, 1.3, 2.5):
		hb.box(mat("metal"), (0, 0, z), (L, 0.03, 0.03), (0.6, 0.6, 0.6))
	# сетка-рабица: частая решётка тонкими прутками (в игре читается как сетка)
	n = 14
	for i in range(n + 1):
		x = -L / 2 + L * i / n
		if broken and 4 <= i <= 8:
			continue
		hb.beam(mat("metal"), (x, 0.0, 0.1), (x, 0.0, 2.5), 0.012, 0.012, (0.55, 0.55, 0.55))
	for k in range(9):
		z = 0.1 + 2.4 * k / 8
		if broken and 1 <= k <= 5:
			hb.beam(mat("metal"), (-L / 2, 0, z), (-L / 2 + L * 0.28, 0, z), 0.012, 0.012, (0.55, 0.55, 0.55))
			hb.beam(mat("metal"), (L / 2 - L * 0.42, 0, z), (L / 2, 0, z), 0.012, 0.012, (0.55, 0.55, 0.55))
			continue
		hb.beam(mat("metal"), (-L / 2, 0, z), (L / 2, 0, z), 0.012, 0.012, (0.55, 0.55, 0.55))
	for k in range(3):                                                # колючая проволока на козырьке
		z = 2.85 + k * 0.13
		y = -0.15 - k * 0.12
		hb.beam(mat("metal"), (-L / 2, y, z), (L / 2, y, z), 0.015, 0.015, (0.45, 0.42, 0.4))
	for i in range(10):                                               # спираль «егоза» (кольца)
		x = -L / 2 + (i + 0.5) * L / 10
		hb.cyl(mat("metal"), (x, -0.25, 3.1), 0.26, 0.012, "X", 10, col=(0.5, 0.48, 0.45))
	return hb.build(name), None

def concrete_pad(name, L, D):
	"""Бетонная площадка из плит (бункер, плац): трещины и швы — текстура бетона."""
	hb = HB()
	nx, ny = int(L / 6), int(D / 3)
	for i in range(nx):
		for j in range(ny):
			c = 0.75 + 0.2 * ((i * 7 + j * 13) % 5) / 4
			hb.box(mat("concrete"), (-L / 2 + (i + 0.5) * L / nx, -D / 2 + (j + 0.5) * D / ny, 0.06), (L / nx - 0.04, D / ny - 0.04, 0.22), (c, c, c * 0.98))
	return hb.build(name, ao=False), None

def road_dash(name):
	hb = HB()
	hb.box(mat("frame_white"), (0, 0, 0.01), (3.0, 0.12, 0.02), (0.92, 0.92, 0.88))
	return hb.build(name, ao=False), None

def bridge(name):
	"""Бетонный мост 18×7 м: пролётное строение, тротуары, металлические перила, опоры, асфальт сверху."""
	hb = HB()
	L, Wd = 18.0, 7.0
	hb.box(mat("concrete"), (0, 0, -0.45), (L, Wd, 0.6), (0.8, 0.8, 0.78))                 # плита
	hb.box(mat("block"), (0, 0, -0.13), (L, Wd - 1.6, 0.04), (0.35, 0.35, 0.37))              # асфальт
	for sy in (-1, 1):
		hb.box(mat("concrete"), (0, sy * (Wd / 2 - 0.4), -0.05), (L, 0.8, 0.2), (0.75, 0.75, 0.72))   # тротуар
		hb.box(mat("metal_paint"), (0, sy * (Wd / 2 - 0.05), 0.95), (L, 0.06, 0.06), (0.35, 0.45, 0.4))  # перила
		hb.box(mat("metal_paint"), (0, sy * (Wd / 2 - 0.05), 0.5), (L, 0.04, 0.04), (0.35, 0.45, 0.4))
		for i in range(13):
			hb.box(mat("metal_paint"), (-L / 2 + 0.3 + i * (L - 0.6) / 12, sy * (Wd / 2 - 0.05), 0.47), (0.06, 0.06, 0.95), (0.35, 0.45, 0.4))
	for x in (-L / 2 + 0.6, -3.0, 3.0, L / 2 - 0.6):                                           # опоры
		hb.box(mat("concrete"), (x, 0, -2.6), (0.9, Wd * 0.8, 4.0), (0.7, 0.7, 0.68))
	return hb.build(name), None

def sign(name, kind):
	"""Дорожный знак на стойке: town — белый прямоугольник «населённый пункт» (без надписи), round — круглый (красная кайма), info — синий."""
	hb = HB()
	hb.cyl(mat("metal_paint"), (0, 0, 1.25), 0.035, 2.5, "Z", 8, col=(0.6, 0.6, 0.6))
	if kind == "town":
		hb.box(mat("frame_white"), (0, -0.04, 2.15), (1.0, 0.03, 0.6), (0.95, 0.95, 0.92))
		hb.box(mat("frame_white"), (0, -0.06, 2.15), (0.85, 0.01, 0.12), (0.05, 0.05, 0.05))
	elif kind == "round":
		hb.cyl(mat("frame_white"), (0, -0.04, 2.1), 0.35, 0.03, "Y", 20, col=(0.75, 0.08, 0.06))
		hb.cyl(mat("frame_white"), (0, -0.06, 2.1), 0.27, 0.01, "Y", 20, col=(0.95, 0.95, 0.92))
		hb.box(mat("frame_white"), (0, -0.075, 2.1), (0.28, 0.01, 0.12), (0.05, 0.05, 0.05))
	else:
		hb.box(mat("frame_white"), (0, -0.04, 2.1), (0.7, 0.03, 0.7), (0.12, 0.3, 0.65))
		hb.box(mat("frame_white"), (0, -0.06, 2.1), (0.12, 0.01, 0.45), (0.95, 0.95, 0.92))
	return hb.build(name), None

def lamp_post(name):
	"""Уличный фонарь: бетонная опора 8 м, кронштейн, светильник."""
	hb = HB()
	hb.cyl(mat("concrete"), (0, 0, 4.0), 0.12, 8.0, "Z", 8, r2=0.08, col=(0.8, 0.8, 0.78))
	hb.beam(mat("metal_paint"), (0, 0, 7.6), (1.4, 0, 7.9), 0.05, col=(0.4, 0.4, 0.4))
	hb.box(mat("metal_paint"), (1.55, 0, 7.82), (0.6, 0.25, 0.12), (0.35, 0.35, 0.35))
	hb.box(mat("headlight"), (1.55, 0, 7.75), (0.5, 0.2, 0.02), (1, 1, 1))
	return hb.build(name), None

def wire_unit(name):
	"""Провод ЛЭП длиной 1 м вдоль X (растягивается при расстановке)."""
	hb = HB()
	hb.box(mat("frame"), (0.5, 0, 0), (1.0, 0.018, 0.018), (0.2, 0.2, 0.2))
	return hb.build(name, ao=False), None

EXTRA = {
	"road_dash": lambda: road_dash("road_dash"),
	"bridge": lambda: bridge("bridge"),
	"sign_town": lambda: sign("sign_town", "town"),
	"sign_round": lambda: sign("sign_round", "round"),
	"sign_info": lambda: sign("sign_info", "info"),
	"lamp_post": lambda: lamp_post("lamp_post"),
	"wire_unit": lambda: wire_unit("wire_unit"),
	"fence_prof_a": lambda: fence_prof("fence_prof_a", (0.62, 0.48, 0.40)),
	"fence_prof_b": lambda: fence_prof("fence_prof_b", (0.36, 0.70, 0.42)),
	"fence_mil_a": lambda: fence_mil("fence_mil_a", False),
	"fence_mil_b": lambda: fence_mil("fence_mil_b", True),
	"concrete_pad": lambda: concrete_pad("concrete_pad", 36.0, 30.0),
}

JOBS = {}
for _n, _s in TYPES.items():
	JOBS[_n] = (lambda n=_n, s=_s: house(n, s, zlib.crc32(n.encode())))
JOBS.update(EXTRA)

# ---------------- показ / самостоятельный запуск ----------------
def preview(objs, path, cut=False, res=(1600, 1000), samples=32, persp=False, pad=16.0, dist_k=0.95, elev=None):
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = samples; sc.cycles.use_denoising = True
	sc.view_settings.view_transform = "AgX"
	if sc.world is None or "pv" not in sc.world:
		w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True; w["pv"] = 1
		hdr = "/tmp/claude-0/trees/dl/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
		N, Lk = w.node_tree.nodes, w.node_tree.links
		if os.path.exists(hdr):
			N.clear()
			bg = N.new("ShaderNodeBackground"); bg.inputs["Strength"].default_value = 0.8
			ev = N.new("ShaderNodeTexEnvironment"); ev.image = bpy.data.images.load(hdr)
			Lk.new(ev.outputs[0], bg.inputs[0]); o = N.new("ShaderNodeOutputWorld"); Lk.new(bg.outputs[0], o.inputs[0])
		sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3.0; sun.data.angle = 0.02
		sun.rotation_euler = (math.radians(45), 0, math.radians(-35)); sc.collection.objects.link(sun)
		for m in bpy.data.materials:                                    # цвет вершин в превью (в игре Godot умножает сам)
			if not m.use_nodes or "Principled BSDF" not in m.node_tree.nodes:
				continue
			nt = m.node_tree; b = nt.nodes["Principled BSDF"]
			ca = nt.nodes.new("ShaderNodeVertexColor"); ca.layer_name = "Color"
			mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"; mix.inputs["Factor"].default_value = 1.0
			src = b.inputs["Base Color"].links[0].from_socket if b.inputs["Base Color"].links else None
			if src:
				nt.links.new(src, mix.inputs[6])
			else:
				mix.inputs[6].default_value = b.inputs["Base Color"].default_value
			nt.links.new(ca.outputs["Color"], mix.inputs[7]); nt.links.new(mix.outputs[2], b.inputs["Base Color"])
		gm = bpy.data.materials.new("g"); gm.use_nodes = True
		gt = gm.node_tree.nodes.new("ShaderNodeTexImage")
		gpath = "/tmp/claude-0/trees/dl/aerial_grass_rock_diff_2k.jpg"
		if os.path.exists(gpath):
			gt.image = bpy.data.images.load(gpath)
			tc = gm.node_tree.nodes.new("ShaderNodeTexCoord"); mp = gm.node_tree.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (250, 250, 1)
			gm.node_tree.links.new(tc.outputs["UV"], mp.inputs[0]); gm.node_tree.links.new(mp.outputs[0], gt.inputs[0])
			gm.node_tree.links.new(gt.outputs[0], gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
		bpy.ops.mesh.primitive_plane_add(size=1000); g = bpy.context.object; g.data.materials.append(gm)
	xs = [o.location.x for o in objs]; ys = [o.location.y for o in objs]
	cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
	span = max(max(xs) - min(xs), (max(ys) - min(ys)) * 1.6) + pad
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
	cam.data.clip_end = 2000
	el = math.radians(elev if elev is not None else (62 if cut else 38))
	d = Vector((-0.45, -math.cos(el), math.sin(el))).normalized()
	look = Vector((cx, cy, 2.0 if pad > 8 else 0.8))
	if persp:
		cam.data.lens = 32
		cam.location = look + d * span * dist_k
	else:
		cam.data.type = "ORTHO"
		cam.data.ortho_scale = span
		cam.location = look + d * 150
	cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
	sc.render.resolution_x, sc.render.resolution_y = res
	sc.render.filepath = path
	bpy.ops.render.render(write_still=True)
	bpy.data.objects.remove(cam)

if __name__ == "__main__":
	OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/houses/out"
	os.makedirs(OUT, exist_ok=True)
	only = [x for x in os.environ.get("ONLY", "").split(",") if x]
	bpy.ops.wm.read_factory_settings(use_empty=True)
	shells, roofs = [], []
	i = 0
	cols = int(os.environ.get("COLS", "4"))
	for n, s in TYPES.items():
		if only and n not in only:
			continue
		sh, rf = house(n, s, zlib.crc32(n.encode()))
		sh.location = rf.location = Vector(((i % cols) * 16.0, -(i // cols) * 16.0, 0))
		i += 1
		shells.append(sh); roofs.append(rf)
		print("HOUSE %-18s оболочка %d тр., крыша %d тр." % (n, sum(len(p.vertices) - 2 for p in sh.data.polygons), sum(len(p.vertices) - 2 for p in rf.data.polygons)), flush=True)
	if os.environ.get("SHOW", "1") == "1":
		preview(shells + roofs, os.path.join(OUT, "houses.png"), persp=os.environ.get("PERSP") == "1")
		for r in roofs:
			r.hide_render = True
		preview(shells, os.path.join(OUT, "houses_cut.png"), cut=True)
