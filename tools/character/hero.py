# Главный герой: обычный мужчина ~1,78 м в гражданском (футболка, джинсы, кроссовки), короткая стрижка, щетина.
# Основа — реалистичное тело «Human Base Meshes» (Blender Studio, CC0): GEO-body_male_realistic, A-поза.
# Одежда строится из поверхности тела: участок сглаживается (ткань не облегает мышцы) и выносится наружу на зазор
# (проверка по ближайшей точке тела — нигде не проваливается внутрь). Тело под одеждой удаляется.
# Скелет — имена как у Mixamo без префикса (Hips, Spine, LeftArm…); веса тела — автоматически, одежда берёт их с тела.
#   скачать основу (один раз):  bash tools/character/get_base.sh
#   /tmp/claude-0/blender/v/bin/python -I tools/character/hero.py <out_dir>   → hero.glb + рендеры hero_*.png
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/hero"
SRC = os.environ.get("HBM", "/tmp/claude-0/hbm/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend")
SCALE = 1.057                                                         # 1,684 → 1,78 м
os.makedirs(OUT, exist_ok=True)

def srgb2lin(c):
	return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)
def mix(a, b, t):
	return tuple(x + (y - x) * t for x, y in zip(a, b))

# ---------------- основа ----------------
bpy.ops.wm.open_mainfile(filepath=SRC, load_ui=False)
KEEP = {"GEO-body_male_realistic": "body", "GEO-body_male_realistic.eye.L": "eye_L", "GEO-body_male_realistic.eye.R": "eye_R"}
for o in list(bpy.data.objects):
	if o.name not in KEEP:
		bpy.data.objects.remove(o)
scn = bpy.context.scene
for o in list(bpy.data.objects):
	o.name = KEEP[o.name]
	if not o.users_collection:
		scn.collection.objects.link(o)
body = bpy.data.objects["body"]
off = body.location.copy()
bpy.context.view_layer.objects.active = body
for o in bpy.context.view_layer.objects:
	o.select_set(o == body)
for m in list(body.modifiers):
	if m.type == "MULTIRES":
		bpy.ops.object.multires_base_apply(modifier=m.name)          # базовая сетка принимает форму скульпта
	body.modifiers.remove(m)
for o in bpy.data.objects:                                           # всё в начало координат, масштаб — в саму сетку
	o.data.transform(o.matrix_world)
	o.matrix_world = Matrix.Identity(4)
	o.data.transform(Matrix.Translation(-Vector((off.x, off.y, 0))))
	o.data.transform(Matrix.Scale(SCALE, 4))
	o.data.materials.clear()
	for p in o.data.polygons:
		p.use_smooth = True

def centre(o):
	c = Vector((0, 0, 0))
	for v in o.data.vertices:
		c += v.co
	return c / max(1, len(o.data.vertices))
EYE_L, EYE_R = centre(bpy.data.objects["eye_L"]), centre(bpy.data.objects["eye_R"])
EYE = (EYE_L + EYE_R) / 2
for v in body.data.vertices:                                           # пах — гладко (под джинсами), иначе ткань «вытягивается» клином
	p = v.co
	if abs(p.x) < 0.075 * SCALE and 0.74 * SCALE < p.z < 0.95 * SCALE and p.y < -0.075 * SCALE:
		p.y = -0.075 * SCALE + (p.y + 0.075 * SCALE) * 0.15

# ---------------- суставы (замер по сетке, × масштаб) ----------------
J = {}
def j(n, x, y, z):
	J[n] = Vector((x, y, z)) * SCALE
j("Hips", 0, 0.0, 0.965); j("Spine", 0, 0.005, 1.05); j("Spine1", 0, 0.01, 1.17); j("Spine2", 0, 0.01, 1.29)
j("Neck", 0, -0.01, 1.445); j("Head", 0, -0.025, 1.535); j("HeadTop", 0, -0.035, 1.684)
for s, sx in (("Left", 1), ("Right", -1)):
	j(s + "Shoulder", sx * 0.03, -0.005, 1.39); j(s + "Arm", sx * 0.165, 0.0, 1.355)
	j(s + "ForeArm", sx * 0.30, 0.01, 1.095); j(s + "Hand", sx * 0.39, -0.035, 0.885); j(s + "HandEnd", sx * 0.43, -0.12, 0.74)
	j(s + "UpLeg", sx * 0.09, 0.0, 0.915); j(s + "Leg", sx * 0.125, -0.005, 0.50); j(s + "Foot", sx * 0.172, 0.045, 0.08)
	j(s + "ToeBase", sx * 0.205, -0.075, 0.03); j(s + "ToeEnd", sx * 0.22, -0.13, 0.02)
BONES = [("Hips", "Hips", "Spine", None), ("Spine", "Spine", "Spine1", "Hips"), ("Spine1", "Spine1", "Spine2", "Spine"),
	("Spine2", "Spine2", "Neck", "Spine1"), ("Neck", "Neck", "Head", "Spine2"), ("Head", "Head", "HeadTop", "Neck")]
for s in ("Left", "Right"):
	BONES += [(s + "Shoulder", s + "Shoulder", s + "Arm", "Spine2"), (s + "Arm", s + "Arm", s + "ForeArm", s + "Shoulder"),
		(s + "ForeArm", s + "ForeArm", s + "Hand", s + "Arm"), (s + "Hand", s + "Hand", s + "HandEnd", s + "ForeArm"),
		(s + "UpLeg", s + "UpLeg", s + "Leg", "Hips"), (s + "Leg", s + "Leg", s + "Foot", s + "UpLeg"),
		(s + "Foot", s + "Foot", s + "ToeBase", s + "Leg"), (s + "ToeBase", s + "ToeBase", s + "ToeEnd", s + "Foot")]
S = SCALE
HC = Vector((0, EYE.y + 0.085 * S, EYE.z + 0.01 * S))                 # центр головы — за глазами

def seg(p, a, b):
	ab = b - a
	t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
	return (a + ab * t - p).length, t

def arm_t(p):
	"""Для точки руки: (расстояние до плеча-локтя, доля вдоль плеча 0..1) — ближайшая сторона."""
	s = "Left" if p.x > 0 else "Right"
	return seg(p, J[s + "Arm"], J[s + "ForeArm"]), seg(p, J[s + "ForeArm"], J[s + "Hand"])

def is_arm(p):
	(d1, t1), (d2, t2) = arm_t(p)
	return (abs(p.x) > 0.13 * S and p.z > 0.68 * S and (d1 < 0.075 * S or d2 < 0.06 * S or abs(p.x) > 0.25 * S)) and not (t1 < 0.02 and d1 > 0.05 * S)

# ---------------- одежда ----------------
BV = None
BOUND = {}
def body_bvh():
	bm = bmesh.new(); bm.from_mesh(body.data); bm.normal_update()
	t = BVHTree.FromBMesh(bm)
	bm.free()
	return t

def cloth(name, pred, gap, smooth=8, fac=0.5, thick=0.004, flat_sole=False):
	gapf = gap if callable(gap) else (lambda p, g=gap: g)
	bm = bmesh.new(); bm.from_mesh(body.data)
	dl = [f for f in bm.faces if not pred(f.calc_center_median())]
	bmesh.ops.delete(bm, geom=dl, context="FACES")
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	bnd = [v for v in bm.verts if v.is_boundary]
	for _ in range(12):                                              # край ткани ровный (выбор граней даёт зубцы)
		new = {}
		for v in bnd:
			nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
			if len(nb) == 2:
				new[v] = v.co * 0.4 + (nb[0].co + nb[1].co) * 0.3
		for v, c in new.items():
			v.co = c
	inner = [v for v in bm.verts if not v.is_boundary]
	for _ in range(smooth):                                          # ткань натянута поверх мышц: сгладить и вытолкнуть наружу, повторить
		bmesh.ops.smooth_vert(bm, verts=inner, factor=fac, use_axis_x=True, use_axis_y=True, use_axis_z=True)
		for v in bm.verts:
			q, n, i, d = BV.find_nearest(v.co)
			if q is not None:
				g = gapf(q)
				out = (v.co - q).dot(n)
				if out < g:
					v.co += n * (g - out)
	for _ in range(3):                                               # наружу на зазор от тела — по ближайшей точке
		for v in bm.verts:
			q, n, i, d = BV.find_nearest(v.co)
			if q is None:
				continue
			out = (v.co - q).dot(n)
			g = gapf(q)
			if out < g:
				v.co += n * (g - out)
		bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.25, use_axis_x=True, use_axis_y=True, use_axis_z=True)
	for v in bm.verts:
		q, n, i, d = BV.find_nearest(v.co)
		if q is not None and ((v.co - q).dot(n) < gapf(q) * 0.8 or (v.co - q).length > 0.05 * S):
			v.co = q + n * gapf(q)                                     # не внутрь тела и не «плавником» наружу
	if flat_sole:
		for v in bm.verts:
			if v.co.z < 0.018:
				v.co.z = 0.0
	BOUND[name] = [(e.verts[0].co.copy(), e.verts[1].co.copy(), (e.link_faces[0].calc_center_median() - (e.verts[0].co + e.verts[1].co) / 2).normalized())
		for e in bm.edges if e.is_boundary and e.link_faces]                                    # края — для окантовок
	if thick:
		bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
		for v in bm.verts:                                             # вырожденная нормаль (пах, подмышка) — вершину на место
			q, n, i, d = BV.find_nearest(v.co)
			if q is not None and (v.co - q).length > 0.055 * S:
				v.co = q + n * gapf(q) * 0.7
	me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
	o = bpy.data.objects.new(name, me); scn.collection.objects.link(o)
	for p in me.polygons:
		p.use_smooth = True
	return o

def neck_open(p):                                                      # вырез горловины: спереди ниже
	r = math.hypot(p.x, p.y + 0.01 * S)
	front = max(0.0, -p.y / (0.08 * S))
	return p.z > (1.415 - 0.035 * min(1.0, front)) * S and r < 0.085 * S

def shirt_pred(p):
	if p.z < 0.88 * S or p.z > 1.48 * S or neck_open(p) or (p - HC).length < 0.15 * S:
		return False
	if p.z > 1.40 * S and math.hypot(p.x, p.y) < 0.075 * S or p.z > 1.415 * S and abs(p.x) < 0.11 * S and p.y < -0.02 * S:
		return False                                                    # шея и под подбородком
	if is_arm(p):
		(d1, t1), (d2, t2) = arm_t(p)
		return (t1 < 1.0 and d1 < 0.085 * S) or (t2 < 0.42 and d2 < 0.07 * S)   # рукав закатан до середины предплечья
	return abs(p.x) < 0.24 * S

def jeans_pred(p):
	if p.z > 0.985 * S or p.z < 0.095 * S or is_arm(p):
		return False
	return True

def shoe_pred(p):
	return p.z < 0.13 * S and abs(p.x) > 0.08 * S

# ---------------- обычная фигура: мышцы мягче (объём сохраняется), небольшой живот ----------------
def soften_body():
	bm = bmesh.new(); bm.from_mesh(body.data)
	vs = [v for v in bm.verts if 0.14 * S < v.co.z < 1.43 * S and not (abs(v.co.x) > 0.33 * S and v.co.z < 0.95 * S)]   # без головы, кистей, стоп
	for _ in range(4):
		bmesh.ops.smooth_laplacian_vert(bm, verts=vs, lambda_factor=0.35, lambda_border=0.0, use_x=True, use_y=True, use_z=True, preserve_volume=True)
	for v in bm.verts:
		p = v.co
		if abs(p.x) < 0.16 * S and 0.93 * S < p.z < 1.24 * S and p.y < 0.0:          # живот чуть вперёд
			k = math.sin(math.pi * (p.z - 0.93 * S) / (0.31 * S)) * max(0.0, 1 - abs(p.x) / (0.16 * S)) ** 0.7
			p.y -= 0.018 * S * k
		if abs(p.x) > 0.04 * S and 0.93 * S < p.z < 1.10 * S and p.y > -0.04 * S and abs(p.x) < 0.18 * S:   # бока мягче
			k = math.sin(math.pi * (p.z - 0.93 * S) / (0.17 * S))
			p.x += math.copysign(0.006 * S * k, p.x)
	bm.normal_update()
	bm.to_mesh(body.data); bm.free()
soften_body()
BV = body_bvh()
shirt = cloth("shirt", shirt_pred, lambda p: (0.011 + 0.008 * max(0.0, min(1.0, (1.25 * S - p.z) / (0.3 * S)))) * S, smooth=14, fac=0.5, thick=0.004)
jeans = cloth("jeans", jeans_pred, lambda p: (0.014 + 0.018 * max(0.0, min(1.0, (0.62 * S - p.z) / (0.3 * S)))) * S, smooth=14, fac=0.5, thick=0.004)   # прямые: ниже колена свободнее
SOLES = []
LACES = []
def shoe(sx):
	"""Кроссовок по контуру стопы: сечения поперёк стопы (ширина и верх по сетке ноги + запас, сглажено), плоская подошва."""
	pts = [v.co.copy() for v in body.data.vertices if v.co.z < 0.13 * S and v.co.x * sx > 0.08 * S]
	heel = max(pts, key=lambda p: p.y)
	toe = min(pts, key=lambda p: p.y)
	ax = Vector((toe.x - heel.x, toe.y - heel.y, 0)).normalized()
	side = Vector((-ax.y, ax.x, 0))
	L = (toe - heel).dot(ax)
	N = 14
	W0, W1, TOP = [], [], []
	for i in range(N + 1):
		t = i / N
		sl = [p for p in pts if abs((p - heel).dot(ax) - t * L) < L / N * 0.8] or pts
		ws = [(p - heel).dot(side) for p in sl]
		W0.append(min(ws)); W1.append(max(ws)); TOP.append(min(max(p.z for p in sl), 0.12 * S))
	for _ in range(3):                                                  # сгладить контур
		for A in (W0, W1, TOP):
			A[:] = [A[0]] + [(A[i - 1] + 2 * A[i] + A[i + 1]) / 4 for i in range(1, N)] + [A[N]]
	def sect(i, m):
		t = i / N
		k = math.sin(math.pi * min(1.0, t * 1.05)) ** 0.35 if t > 0.85 or t < 0.05 else 1.0  # скругление носка и пятки
		w0, w1 = W0[i] - m, W1[i] + m
		c = heel + ax * (t * L + (-m if i == 0 else (m * 1.3 if i == N else 0.0)))
		return c, (w0 + w1) / 2, (w1 - w0) / 2 * max(k, 0.55), k
	rings = []
	for i in range(N + 1):
		c, mid, hw, k = sect(i, 0.012 * S)
		top = (TOP[i] + 0.012 * S) * max(k, 0.5)
		ring = []
		for j in range(16):
			a = j / 16 * 2 * math.pi
			cy, cz = math.cos(a), math.sin(a)
			z = top * (0.5 + 0.5 * cz) if cz > 0 else 0.012 * S * (1 + cz)
			ring.append(c + side * (mid + hw * (abs(cy) ** 0.6) * (1 if cy >= 0 else -1)) + Vector((0, 0, z)))
		rings.append(ring)
	bm = bmesh.new()
	vs = [[bm.verts.new(p) for p in r] for r in rings]
	for i in range(N):
		for j in range(16):
			bm.faces.new([vs[i][j], vs[i][(j + 1) % 16], vs[i + 1][(j + 1) % 16], vs[i + 1][j]])
	bm.faces.new(vs[0][::-1]); bm.faces.new(vs[N])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True, smooth=0.6)
	for v in bm.verts:
		if v.co.z < 0.004 * S:
			v.co.z = 0.0
	ring = []                                                           # подошва: тот же контур на 4 мм шире, плита 2,6 см
	for i in range(N + 1):
		c, mid, hw, k = sect(i, 0.0125 * S)
		ring.append(c + side * (mid - hw))
	for i in range(N, -1, -1):
		c, mid, hw, k = sect(i, 0.0125 * S)
		ring.append(c + side * (mid + hw))
	sb = bmesh.new()
	lo = [sb.verts.new((p.x, p.y, 0.0)) for p in ring]
	hi = [sb.verts.new((p.x, p.y, 0.022 * S)) for p in ring]
	sb.faces.new(lo[::-1]); sb.faces.new(hi)
	for i in range(len(ring)):
		k2 = (i + 1) % len(ring)
		sb.faces.new([lo[i], lo[k2], hi[k2], hi[i]])
	bmesh.ops.recalc_face_normals(sb, faces=sb.faces)
	sm = bpy.data.meshes.new("sole"); sb.to_mesh(sm); sb.free()
	so = bpy.data.objects.new("sole", sm); scn.collection.objects.link(so)
	SOLES.append(so)
	# шнурки поперёк подъёма, язычок, задник
	lb = bmesh.new()
	rot = Matrix((side.to_3d(), ax.to_3d(), Vector((0, 0, 1)))).transposed().to_4x4()
	for i in range(5, 11):
		c, mid, hw, k = sect(i, 0.012 * S)
		top = (TOP[i] + 0.012 * S) * max(k, 0.5)
		pc = c + side * mid + Vector((0, 0, top + 0.002 * S))
		bmesh.ops.create_cube(lb, size=1.0, matrix=Matrix.Translation(pc) @ rot @ Matrix.Diagonal((hw * 0.9, 0.006 * S, 0.004 * S, 1)))
	c, mid, hw, k = sect(11, 0.012 * S)
	pc = c + side * mid + Vector((0, 0, (TOP[11] + 0.02 * S)))
	bmesh.ops.create_cube(lb, size=1.0, matrix=Matrix.Translation(pc) @ rot @ Matrix.Diagonal((hw * 0.8, 0.05 * S, 0.006 * S, 1)))  # язычок
	c, mid, hw, k = sect(0, 0.012 * S)
	pc = c + side * mid + Vector((0, 0, TOP[0] + 0.01 * S))
	bmesh.ops.create_cube(lb, size=1.0, matrix=Matrix.Translation(pc) @ rot @ Matrix.Diagonal((0.03 * S, 0.012 * S, 0.035 * S, 1)))  # задник
	lm = bpy.data.meshes.new("laces"); lb.to_mesh(lm); lb.free()
	lo_ = bpy.data.objects.new("laces", lm); scn.collection.objects.link(lo_)
	LACES.append(lo_)
	me = bpy.data.meshes.new("shoe"); bm.to_mesh(me); bm.free()
	o = bpy.data.objects.new("shoe", me); scn.collection.objects.link(o)
	for p in me.polygons:
		p.use_smooth = True
	return o
shoes = shoe(1)
shoes2 = shoe(-1)

# ---------------- складки ткани ----------------
def noise3(p, f):
	return (math.sin(p.x * f * 1.3 + p.z * f * 0.7) * math.sin(p.y * f * 1.1 - p.z * f * 0.9) + math.sin(p.z * f * 2.1 + p.x * f * 0.5) * 0.5) / 1.5

def wrinkle(o, fn):
	me = o.data
	me.calc_normals_split() if hasattr(me, "calc_normals_split") else None
	for v in me.vertices:
		d = fn(v.co)
		if d:
			v.co += v.normal * d

def shirt_folds(p):
	d = 0.0
	if p.z < 1.0 * S:                                                    # низ навыпуск — волна
		d += 0.004 * S * math.sin(p.x * 60 + p.y * 40) * (1.0 * S - p.z) / (0.12 * S)
	if 1.25 * S < p.z < 1.38 * S and 0.11 * S < abs(p.x) < 0.2 * S:      # подмышки — тянущиеся складки
		d += 0.003 * S * math.sin((p.z + abs(p.x)) * 160)
	d += 0.0015 * S * noise3(p, 45)
	return d
def jeans_folds(p):
	d = 0.0
	if p.z < 0.24 * S:                                                   # гармошка над кроссовками
		d += 0.005 * S * math.sin(p.z * 260 + math.atan2(p.y, p.x) * 2) * (0.24 * S - p.z) / (0.14 * S)
	if 0.44 * S < p.z < 0.58 * S and p.y > 0.0:                          # под коленом
		d += 0.0035 * S * math.sin(p.z * 220)
	if 0.80 * S < p.z < 0.9 * S and abs(p.x) < 0.1 * S and p.y < 0.0:   # «усы» у паха
		d += 0.003 * S * math.sin((p.z - abs(p.x) * 0.8) * 300)
	d += 0.0012 * S * noise3(p, 50)
	return d
wrinkle(shirt, shirt_folds)
wrinkle(jeans, jeans_folds)

# ---------------- окантовки: ворот, рукава, низ футболки, пояс и подгиб джинсов ----------------
def hems(src, name, r, only=None, w=0.012):
	"""Окантовка: полоса вдоль открытого края ткани, на r поверх, шириной w внутрь ткани (двусторонняя)."""
	bm = bmesh.new()
	for a_, b_, din in BOUND[src.name]:
		if only and not (only(a_) and only(b_)):
			continue
		m_ = (a_ + b_) / 2
		q, n, _, _ = BV.find_nearest(m_)
		n = n if q is not None else Vector((0, 0, 1))
		off = n * r
		vs = [bm.verts.new(a_ + off), bm.verts.new(b_ + off), bm.verts.new(b_ + off + din * w * S), bm.verts.new(a_ + off + din * w * S)]
		bm.faces.new(vs)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
	bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.002)
	me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
	o = bpy.data.objects.new(name, me); scn.collection.objects.link(o)
	for p in o.data.polygons:
		p.use_smooth = True
	return o
# окантовки полосой выглядели «рюшами» — края ткани сглажены, отдельной окантовки нет
# пояс джинсов и ремень
def belt():
	bm = bmesh.new()
	ring = []
	z = 0.975 * S
	for k in range(48):
		a = k / 48 * 2 * math.pi
		d = Vector((math.cos(a), math.sin(a), 0))
		lo, hi = Vector((0, 0, z)), d * 0.21 * S + Vector((0, 0, z))
		hit = BV.ray_cast(hi, -d, 0.25 * S)
		r = (hit[0] - Vector((0, 0, z))).length if hit[0] else 0.15 * S
		ring.append(Vector((0, 0, z)) + d * (r + 0.016 * S))
	vs = [[bm.verts.new(p + Vector((0, 0, dz))) for p in ring] for dz in (-0.018 * S, 0.018 * S)]
	for k in range(48):
		k2 = (k + 1) % 48
		bm.faces.new([vs[0][k], vs[0][k2], vs[1][k2], vs[1][k]])
	bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.004 * S)
	me = bpy.data.meshes.new("belt"); bm.to_mesh(me); bm.free()
	o = bpy.data.objects.new("belt", me); scn.collection.objects.link(o)
	# пряжка
	bk = bmesh.new()
	bmesh.ops.create_cube(bk, size=1.0, matrix=Matrix.Translation(ring[36] + Vector((0, -0.004 * S, 0))) @ Matrix.Diagonal((0.05 * S, 0.008 * S, 0.04 * S, 1)))
	bm2 = bpy.data.meshes.new("buckle"); bk.to_mesh(bm2); bk.free()
	b2 = bpy.data.objects.new("buckle", bm2); scn.collection.objects.link(b2)
	return o, b2
belt_o, buckle = belt()

# ---------------- волосы ----------------
def hair_pred(p):
	r = p - HC
	if r.length > 0.16 * S:
		return False
	d = r.normalized()
	front = max(0.0, -d.y)
	back = max(0.0, d.y)
	line = 0.055 * S * front + (0.0) * (1 - front - back) + (-0.085 * S) * back          # линия роста: лоб, виски, затылок
	if abs(r.x) > 0.06 * S and -0.05 * S < r.z < 0.02 * S and r.y > -0.04 * S:
		return False                                                    # уши открыты
	return r.z > line
def hair_top(p):                                                       # объём волос — только внутри окрашенной стрижки
	return hair_pred(p - Vector((0, 0, 0.022 * S)))
def beard_pred(p):                                                    # короткая борода: челюсть, подбородок, усы (губы открыты)
	if (p - HC).length > 0.17 * S or p.y > EYE.y + 0.06 * S:
		return False
	e = p - EYE
	ax = abs(e.x)
	if -0.075 * S < e.z < -0.055 * S and ax < 0.026 * S:
		return False                                                    # губы
	if e.z > -0.045 * S or e.z < -0.15 * S or ax > 0.075 * S:
		return False
	if e.z > -0.075 * S and ax < 0.034 * S and e.z < -0.052 * S:
		return True                                                     # усы над губой
	return e.z < -0.06 * S or ax > 0.045 * S
def tufts(o, k):
	"""Пряди: вершины наружу по нормали на шум — волосы не «шлем», а ёжик с вихрами."""
	me = o.data
	for v in me.vertices:
		c = v.co
		n = 0.5 + 0.5 * math.sin(c.x * 260 + math.sin(c.y * 190) * 2.0) * math.sin(c.y * 230 + math.sin(c.z * 210) * 2.0)
		v.co = c + v.normal * k * S * n
def hair_depth(p):                                                    # насколько точка выше линии роста волос (м)
	r = p - HC
	d = r.normalized()
	front = max(0.0, -d.y); back = max(0.0, d.y)
	return r.z - (0.055 * S * front + (-0.085 * S) * back)
def hair_gap(p):                                                      # у линии роста ~0 (край не ступенькой), к макушке — 1,3 см
	k = max(0.0, min(1.0, hair_depth(p) / (0.05 * S)))
	return (0.0015 + 0.012 * k * k * (3 - 2 * k)) * S
# кепка: купол по голове (над линией роста волос), козырёк вперёд — образ выжившего, читается в комиксе
hair = cloth("hair", hair_pred, 0.011 * S, smooth=6, fac=0.5, thick=0.004)
def visor():
	vs = [v.co.copy() for v in hair.data.vertices]
	fw = []
	for i in range(13):                                              # передний край купола: дуга −52°…+52° от лба
		a = math.radians(-52 + 104 * i / 12)
		d = Vector((math.sin(a), -math.cos(a), 0))
		best = max((v for v in vs if (v - HC).z < 0.075 * S), key=lambda v: (v - HC).normalized().dot(d) - abs((v - HC).z - 0.06 * S) * 3.0)
		fw.append((best, d, a))
	bm = bmesh.new()
	rows = []
	for (p0, d, a) in fw:
		ext = (0.072 - 0.045 * abs(a) / math.radians(52)) * S              # посередине козырёк длиннее
		row = []
		for k in range(4):
			t = k / 3
			q = p0 + d * ext * t + Vector((0, 0, -0.012 * S * t * t))      # чуть вниз к краю
			row.append(bm.verts.new(q))
		rows.append(row)
	for i in range(len(rows) - 1):
		for k in range(3):
			bm.faces.new((rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.006)
	me = bpy.data.meshes.new("visor"); bm.to_mesh(me); bm.free()
	o = bpy.data.objects.new("visor", me); scn.collection.objects.link(o)
	for p in me.polygons:
		p.use_smooth = True
	return o
visor_o = visor()
# ---------------- цвет ----------------
MATS = {}
def mat(name, rough=0.8, sss=0.0, spec=0.5):
	if name in MATS:
		return MATS[name]
	m = bpy.data.materials.new(name); m.use_nodes = True
	nt = m.node_tree; b = nt.nodes["Principled BSDF"]
	vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Color"
	nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
	b.inputs["Roughness"].default_value = rough
	if sss:
		b.inputs["Subsurface Weight"].default_value = sss
		b.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
		b.inputs["Subsurface Scale"].default_value = 0.008
	MATS[name] = m
	return m

def paint(o, fn, m):
	me = o.data
	cl = me.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
	for p in me.polygons:
		for li in p.loop_indices:
			v = me.vertices[me.loops[li].vertex_index]
			c = srgb2lin(fn(v.co, v.normal))
			cl.data[li].color = (c[0], c[1], c[2], 1.0)
	me.color_attributes.active_color = cl
	me.materials.append(m)

SKIN = (0.80, 0.60, 0.50)
def bump(x, a, b, soft):
	"""1 внутри [a, b], плавно к 0 за край на soft."""
	if x < a:
		return max(0.0, 1 - (a - x) / soft)
	if x > b:
		return max(0.0, 1 - (x - b) / soft)
	return 1.0
def skin_col(p, n):
	c = SKIN
	e = p - EYE
	if hair_pred(p):
		return mix((0.17, 0.12, 0.09), (0.12, 0.085, 0.065), 0.5 + 0.5 * math.sin(p.x * 900) * math.sin(p.y * 800))   # стрижка «ёжиком»
	for k, dz in ((0.6, 0.004), (0.35, 0.008), (0.15, 0.013)):           # край стрижки — мягче
		if hair_pred(p + Vector((0, 0, dz * S))):
			c = mix(c, (0.17, 0.12, 0.09), k)
			break
	if (p - HC).length < 0.17 * S and p.y < EYE.y + 0.07 * S:
		ax = abs(e.x)
		# брови: над глазами
		k = bump(e.z, 0.019 * S, 0.025 * S, 0.003 * S) * bump(ax, 0.014 * S, 0.047 * S, 0.005 * S) * (1.0 if p.y < EYE.y + 0.01 * S else 0.0)
		c = mix(c, (0.22, 0.15, 0.11), 0.85 * k)
		# щетина: челюсть, подбородок, над губой (не на губах)
		lip = bump(e.z, -0.075 * S, -0.06 * S, 0.003 * S) * bump(ax, 0.0, 0.022 * S, 0.004 * S)
		st = bump(e.z, -0.135 * S, -0.045 * S, 0.012 * S) * bump(ax, 0.0, 0.065 * S, 0.012 * S) * (1 - bump(ax, 0.0, 0.03 * S, 0.006 * S) * bump(e.z, -0.058 * S, -0.04 * S, 0.006 * S))
		c = mix(c, (0.40, 0.31, 0.26), 0.6 * st * (1 - lip))            # щетина
		c = mix(c, (0.66, 0.42, 0.38), 0.7 * lip)
		# румянец на щеках и носу
		c = mix(c, (0.85, 0.5, 0.44), 0.18 * bump(e.z, -0.04 * S, -0.01 * S, 0.01 * S) * bump(ax, 0.0, 0.05 * S, 0.01 * S))
	return c
paint(body, skin_col, mat("skin", 0.5, sss=0.2))
for e in ("eye_L", "eye_R"):
	o = bpy.data.objects[e]
	ec = Vector((0, 0, 0))
	for v in o.data.vertices:
		ec += v.co
	ec /= max(1, len(o.data.vertices))
	paint(o, lambda p, n, ec=ec: (0.03, 0.03, 0.03) if (p - ec).normalized().y < -0.95 else ((0.32, 0.36, 0.22) if (p - ec).normalized().y < -0.82 else (0.9, 0.88, 0.84)), mat("eye", 0.08))
TEE = (0.55, 0.13, 0.10)                                              # красная фланель в клетку (клетка — при запекании)
paint(shirt, lambda p, n: mix(TEE, (0.33, 0.08, 0.06), 0.25 * max(0.0, -n.z)), mat("cotton", 0.95))
CAP = (0.26, 0.31, 0.22)                                              # кепка цвета хаки
paint(hair, lambda p, n: mix(CAP, (0.18, 0.21, 0.15), 0.3 * max(0.0, -n.z)), mat("cap", 0.9))
paint(visor_o, lambda p, n: (0.2, 0.24, 0.17), mat("cap", 0.9))
def denim(p, n):
	base = (0.21, 0.28, 0.42)
	fade = max(0.0, 1.0 - abs(p.z - 0.62 * S) / (0.22 * S)) * (0.18 if n.y < -0.2 else 0.08) + max(0.0, 1.0 - abs(p.z - 0.86 * S) / (0.07 * S)) * 0.12
	return mix(base, (0.55, 0.62, 0.72), fade)
paint(jeans, denim, mat("denim", 0.9))
shoe_col = lambda p, n: (0.93, 0.93, 0.91) if p.z < 0.03 * S else ((0.8, 0.8, 0.78) if p.z < 0.038 * S else (0.17, 0.18, 0.2))
paint(shoes2, shoe_col, mat("shoe", 0.65))
_unused = (lambda p, n: (0.93, 0.93, 0.91) if p.z < 0.028 * S else ((0.92, 0.92, 0.9) if (p.z > 0.09 * S and n.y < -0.3) else (0.17, 0.18, 0.2)), mat("shoe", 0.65))
paint(shoes, shoe_col, mat("shoe", 0.65))
for so in SOLES:
	paint(so, lambda p, n: (0.92, 0.92, 0.9), mat("sole", 0.8))
for lc in LACES:
	paint(lc, lambda p, n: (0.9, 0.9, 0.88), mat("laces", 0.9))
paint(belt_o, lambda p, n: (0.22, 0.14, 0.09), mat("leather", 0.5))
paint(buckle, lambda p, n: (0.62, 0.6, 0.56), mat("metal", 0.3))

# ---------------- скелет и веса ----------------
arm_d = bpy.data.armatures.new("hero_rig")
rig = bpy.data.objects.new("hero_rig", arm_d); scn.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
for o in bpy.context.view_layer.objects:
	o.select_set(o == rig)
bpy.ops.object.mode_set(mode="EDIT")
eb = {}
for (n, a, b, par) in BONES:
	e = arm_d.edit_bones.new(n)
	e.head, e.tail = J[a], J[b]
	e.roll = 0.0
	if par:
		e.parent = eb[par]
		e.use_connect = (e.head - eb[par].tail).length < 1e-4
	eb[n] = e
bpy.ops.object.mode_set(mode="OBJECT")
# тело — автоматические веса («тепло»)
for o in bpy.context.view_layer.objects:
	o.select_set(o in (body, rig))
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
used = set(x.group for v in body.data.vertices for x in v.groups if x.weight > 0.01)
empty = [g.name for g in body.vertex_groups if g.index not in used]
print("HERO группы без весов (выборка):", empty)
# одежда, волосы, глаза — веса с ближайшего места тела
for o in [shirt, jeans, shoes, shoes2, belt_o, buckle, hair, visor_o] + SOLES + LACES + [bpy.data.objects["eye_L"], bpy.data.objects["eye_R"]]:
	for (n, a, b, par) in BONES:
		o.vertex_groups.new(name=n)
	dt = o.modifiers.new("dt", "DATA_TRANSFER")
	dt.object = body
	dt.use_vert_data = True
	dt.data_types_verts = {"VGROUP_WEIGHTS"}
	dt.vert_mapping = "POLYINTERP_NEAREST"
	dt.layers_vgroup_select_src = "ALL"
	dt.layers_vgroup_select_dst = "NAME"
	bpy.context.view_layer.objects.active = o
	for x in bpy.context.view_layer.objects:
		x.select_set(x == o)
	bpy.ops.object.modifier_apply(modifier="dt")
# тело под одеждой — убрать (кроме полосы у краёв одежды)
bm = bmesh.new(); bm.from_mesh(body.data)
cov = set(f for f in bm.faces if (shirt_pred(c := f.calc_center_median()) or jeans_pred(c) or shoe_pred(c)))
ring = set(f for f in cov if any(g not in cov for e in f.edges for g in e.link_faces))
for _ in range(3):
	ring |= set(g for f in ring for e in f.edges for g in e.link_faces if g in cov)
bmesh.ops.delete(bm, geom=list(cov - ring), context="FACES")
bm.to_mesh(body.data); bm.free()

# ---------------- текстуры: процедурный узор → картинка (цвет + нормали) ----------------
TEX_OUT = os.path.join(OUT, "tex")
os.makedirs(TEX_OUT, exist_ok=True)
scn.render.engine = "CYCLES"; scn.cycles.device = "CPU"; scn.cycles.samples = 4
scn.render.bake.margin = 6

def nd(nt, t, x=0, **kw):
	n = nt.nodes.new(t)
	for k, v in kw.items():
		if k in n.inputs:
			n.inputs[k].default_value = v
		else:
			setattr(n, k, v)
	return n
def mathn(nt, op, a, b):
	n = nt.nodes.new("ShaderNodeMath"); n.operation = op
	for i, v in enumerate((a, b)):
		if isinstance(v, (int, float)):
			n.inputs[i].default_value = v
		else:
			nt.links.new(v, n.inputs[i])
	return n.outputs[0]
def mixc(nt, a, b, f, mode="MIX"):
	n = nt.nodes.new("ShaderNodeMix"); n.data_type = "RGBA"; n.blend_type = mode
	for sock, v in ((n.inputs[6], a), (n.inputs[7], b), (n.inputs[0], f)):
		if isinstance(v, (int, float)) or isinstance(v, tuple):
			sock.default_value = v if not isinstance(v, tuple) else v + ((1.0,) if len(v) == 3 else ())
		else:
			nt.links.new(v, sock)
	return n.outputs[2]

def noise(nt, co, scale, detail=6.0, rough=0.6):
	n = nd(nt, "ShaderNodeTexNoise", Scale=scale, Detail=detail, Roughness=rough)
	nt.links.new(co, n.inputs["Vector"])
	return n.outputs["Fac"]
def wave(nt, co, scale, direction="X", kind="BANDS", dist=0.0):
	n = nt.nodes.new("ShaderNodeTexWave"); n.wave_type = kind
	if kind == "BANDS":
		n.bands_direction = direction
	n.inputs["Scale"].default_value = scale; n.inputs["Distortion"].default_value = dist
	nt.links.new(co, n.inputs["Vector"])
	return n.outputs["Fac"]

# узоры: (цвет, высота) по цвету вершин vc и координатам co (метры)
def pat_skin(nt, vc, co):
	n1 = noise(nt, co, 90.0); n2 = noise(nt, co, 600.0, 3.0); n3 = noise(nt, co, 12.0, 2.0)
	c = mixc(nt, vc, (0.55, 0.30, 0.26), mathn(nt, "MULTIPLY", n3, 0.18), "MIX")           # пятна красноты
	c = mixc(nt, c, mathn(nt, "ADD", mathn(nt, "MULTIPLY", n1, 0.18), 0.91), 1.0, "MULTIPLY")
	h = mathn(nt, "ADD", mathn(nt, "MULTIPLY", n2, 0.7), mathn(nt, "MULTIPLY", n1, 0.3))
	return c, h, 0.12
def pat_cotton(nt, vc, co):
	rib = wave(nt, co, 900.0, "X"); n1 = noise(nt, co, 40.0, 4.0); n2 = noise(nt, co, 900.0, 2.0)
	c = mixc(nt, vc, mathn(nt, "ADD", mathn(nt, "MULTIPLY", n1, 0.14), 0.9), 1.0, "MULTIPLY")
	c = mixc(nt, c, mathn(nt, "ADD", mathn(nt, "MULTIPLY", rib, 0.08), 0.95), 1.0, "MULTIPLY")
	return c, mathn(nt, "ADD", mathn(nt, "MULTIPLY", rib, 0.6), mathn(nt, "MULTIPLY", n2, 0.4)), 0.35
def pat_denim(nt, vc, co):
	tw = wave(nt, co, 700.0, "DIAGONAL"); n1 = noise(nt, co, 1500.0, 2.0); n2 = noise(nt, co, 25.0, 4.0)
	light = mixc(nt, vc, (0.62, 0.68, 0.78), 0.35)
	c = mixc(nt, vc, light, mathn(nt, "MULTIPLY", mathn(nt, "ADD", tw, n1), 0.18))
	c = mixc(nt, c, mathn(nt, "ADD", mathn(nt, "MULTIPLY", n2, 0.16), 0.9), 1.0, "MULTIPLY")
	return c, mathn(nt, "ADD", mathn(nt, "MULTIPLY", tw, 0.7), mathn(nt, "MULTIPLY", n1, 0.3)), 0.45
def pat_mesh(nt, vc, co):
	v = nd(nt, "ShaderNodeTexVoronoi", Scale=700.0); nt.links.new(co, v.inputs["Vector"])
	d = v.outputs["Distance"]; n1 = noise(nt, co, 60.0, 3.0)
	c = mixc(nt, vc, mathn(nt, "ADD", mathn(nt, "MULTIPLY", d, 0.35), 0.8), 1.0, "MULTIPLY")
	c = mixc(nt, c, mathn(nt, "ADD", mathn(nt, "MULTIPLY", n1, 0.12), 0.92), 1.0, "MULTIPLY")
	return c, d, 0.35
def pat_plain(scale, k, bumpk):
	def f(nt, vc, co):
		n1 = noise(nt, co, scale, 4.0)
		c = mixc(nt, vc, mathn(nt, "ADD", mathn(nt, "MULTIPLY", n1, k), 1.0 - k * 0.5), 1.0, "MULTIPLY")
		return c, n1, bumpk
	return f
def pat_leather(nt, vc, co):
	v = nd(nt, "ShaderNodeTexVoronoi", Scale=900.0); nt.links.new(co, v.inputs["Vector"])
	n1 = noise(nt, co, 50.0, 4.0)
	c = mixc(nt, vc, mathn(nt, "ADD", mathn(nt, "MULTIPLY", n1, 0.3), 0.85), 1.0, "MULTIPLY")
	return c, v.outputs["Distance"], 0.2

def pat_flannel(nt, vc, co):
	bx = wave(nt, co, 9.0, "X"); bz = wave(nt, co, 9.0, "Z")               # клетка: полосы поперёк и вдоль, ~11 см
	fx = wave(nt, co, 27.0, "X"); fz = wave(nt, co, 27.0, "Z")             # тонкие светлые нити
	dx = mathn(nt, "GREATER_THAN", bx, 0.62); dz = mathn(nt, "GREATER_THAN", bz, 0.62)
	dark = mathn(nt, "MINIMUM", mathn(nt, "ADD", dx, dz), 1.4)
	c = mixc(nt, vc, mathn(nt, "SUBTRACT", 1.0, mathn(nt, "MULTIPLY", dark, 0.42)), 1.0, "MULTIPLY")
	ln = mathn(nt, "MULTIPLY", mathn(nt, "GREATER_THAN", fx, 0.93), mathn(nt, "GREATER_THAN", fz, 0.2))
	c = mixc(nt, c, (0.85, 0.75, 0.62), mathn(nt, "MULTIPLY", ln, 0.35))
	n1 = noise(nt, co, 800.0, 2.0)
	return c, mathn(nt, "ADD", mathn(nt, "MULTIPLY", n1, 0.5), mathn(nt, "MULTIPLY", wave(nt, co, 600.0, "DIAGONAL"), 0.5)), 0.3
def pat_hair(nt, vc, co):
	st = wave(nt, co, 400.0, "Z", "BANDS", 6.0); n1 = noise(nt, co, 300.0, 3.0)
	c = mixc(nt, vc, mathn(nt, "ADD", mathn(nt, "MULTIPLY", st, 0.35), 0.75), 1.0, "MULTIPLY")
	return c, mathn(nt, "ADD", st, n1), 0.5

def bake_part(o, name, size, pat, rough, metal=0.0, sss=0.0, reuv=True):
	bpy.context.view_layer.objects.active = o
	for x in bpy.context.view_layer.objects:
		x.select_set(x == o)
	if reuv or not o.data.uv_layers:
		if not o.data.uv_layers:
			o.data.uv_layers.new(name="UVMap")
		bpy.ops.object.mode_set(mode="EDIT")
		bpy.ops.mesh.select_all(action="SELECT")
		bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
		bpy.ops.object.mode_set(mode="OBJECT")
	m = bpy.data.materials.new(name + "_bake"); m.use_nodes = True
	nt = m.node_tree
	bsdf = nt.nodes["Principled BSDF"]
	vc = nd(nt, "ShaderNodeVertexColor", layer_name="Color")
	tc = nt.nodes.new("ShaderNodeTexCoord")
	col, h, bk = pat(nt, vc.outputs["Color"], tc.outputs["Object"])
	nt.links.new(col, bsdf.inputs["Base Color"])
	bump = nd(nt, "ShaderNodeBump", Strength=bk, Distance=0.002)
	nt.links.new(h, bump.inputs["Height"]); nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
	ic = bpy.data.images.new(name + "_c", size, size); ic.colorspace_settings.name = "sRGB"
	inn = bpy.data.images.new(name + "_n", size, size); inn.colorspace_settings.name = "Non-Color"
	tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = ic
	o.data.materials.clear(); o.data.materials.append(m)
	nt.nodes.active = tn
	bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=6)
	tn.image = inn
	bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=6)
	for im in (ic, inn):
		im.filepath_raw = os.path.join(TEX_OUT, im.name + ".png"); im.file_format = "PNG"; im.save()
	# итоговый материал: картинки
	f = bpy.data.materials.new(name); f.use_nodes = True
	ft = f.node_tree; fb = ft.nodes["Principled BSDF"]
	t1 = ft.nodes.new("ShaderNodeTexImage"); t1.image = ic
	t2 = ft.nodes.new("ShaderNodeTexImage"); t2.image = inn
	nm = ft.nodes.new("ShaderNodeNormalMap")
	ft.links.new(t1.outputs["Color"], fb.inputs["Base Color"])
	ft.links.new(t2.outputs["Color"], nm.inputs["Color"]); ft.links.new(nm.outputs["Normal"], fb.inputs["Normal"])
	fb.inputs["Roughness"].default_value = rough
	fb.inputs["Metallic"].default_value = metal
	if sss:
		fb.inputs["Subsurface Weight"].default_value = sss
		fb.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
		fb.inputs["Subsurface Scale"].default_value = 0.008
	o.data.materials.clear(); o.data.materials.append(f)
	print("BAKE", name, size)

if os.environ.get("BAKE", "1") == "1":
	bake_part(body, "hero_skin", int(os.environ.get("SKIN_TEX", "2048")), pat_skin, 0.48, sss=0.2, reuv=True)
	bake_part(shirt, "hero_shirt", 1024, pat_flannel, 0.95)
	bake_part(hair, "hero_cap", 512, pat_cotton, 0.9)
	bake_part(visor_o, "hero_visor", 256, pat_cotton, 0.9)
	bake_part(jeans, "hero_jeans", 1024, pat_denim, 0.9)
	for i, o in enumerate([shoes, shoes2]):
		bake_part(o, "hero_shoe%d" % i, 512, pat_mesh, 0.7)
	for i, o in enumerate(SOLES):
		bake_part(o, "hero_sole%d" % i, 128, pat_plain(300.0, 0.1, 0.3), 0.8)
	for i, o in enumerate(LACES):
		bake_part(o, "hero_laces%d" % i, 128, pat_plain(800.0, 0.15, 0.4), 0.9)
	bake_part(belt_o, "hero_belt", 256, pat_leather, 0.45)
	bake_part(buckle, "hero_buckle", 64, pat_plain(200.0, 0.1, 0.1), 0.3, metal=0.9)
	for e in ("eye_L", "eye_R"):
		bake_part(bpy.data.objects[e], "hero_" + e, 128, pat_plain(3000.0, 0.05, 0.05), 0.05, reuv=False)

# ремень под фланелью навыпуск не виден (пряжка торчала сквозь рубашку) — убрать
for o in (belt_o, buckle):
	bpy.data.objects.remove(o)
# всё в один объект
for b in body.modifiers:
	if b.type == "ARMATURE":
		body.modifiers.remove(b)
body.parent = None
for x in bpy.context.view_layer.objects:
	x.select_set(x.type == "MESH")
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
hero = bpy.context.view_layer.objects.active
hero.name = "hero"
md = hero.modifiers.new("arm", "ARMATURE"); md.object = rig
hero.parent = rig
tri = sum(len(p.vertices) - 2 for p in hero.data.polygons)
print("HERO треугольников %d, вершин %d, костей %d, рост %.2f м" % (tri, len(hero.data.vertices), len(BONES), hero.dimensions.z))

# анимации — мокап CMU (живой человек), перенос на скелет героя: hero_mocap.py / cmu.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_mocap, json
CLIPS_INFO = hero_mocap.make(rig)
json.dump(CLIPS_INFO, open(os.path.join(OUT, "hero_clips.json"), "w"), indent=1, ensure_ascii=False)
bpy.ops.object.select_all(action="DESELECT")
hero.select_set(True); rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "hero.glb"), use_selection=True, export_format="GLB",
	export_vertex_color="NONE", export_image_format="JPEG", export_jpeg_quality=85, export_skins=True, export_animations=True,
	export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1)

if os.environ.get("SHOW", "1") == "1":
	sc = scn
	sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 64; sc.cycles.use_denoising = True
	sc.view_settings.view_transform = "AgX"
	sc.render.resolution_x, sc.render.resolution_y = 900, 1200
	w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
	w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.65, 0.7, 1)
	w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
	for c in list(sc.collection.objects):
		if c.type in ("CAMERA", "LIGHT"):
			bpy.data.objects.remove(c)
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
	sun.data.energy = 3.0; sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
	gm = bpy.data.meshes.new("g"); gb = bmesh.new(); bmesh.ops.create_grid(gb, x_segments=1, y_segments=1, size=5); gb.to_mesh(gm); gb.free()
	g = bpy.data.objects.new("ground", gm); sc.collection.objects.link(g)
	gmat = bpy.data.materials.new("gnd"); gmat.use_nodes = True; gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.25, 0.24, 1); gm.materials.append(gmat)
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
	views = [("front", (0.35, -4.4, 1.15), (0, 0, 0.92), 50), ("side", (4.4, -0.5, 1.15), (0, 0, 0.92), 50),
		("face", (0.22, -0.72, 1.72), (0, -0.05, 1.68), 75), ("back", (-0.9, 4.2, 1.2), (0, 0, 0.92), 50)]
	if os.environ.get("POSE") == "1":                                 # проверка весов: шаг и согнутая рука
		pb = rig.pose.bones
		pb["LeftArm"].rotation_mode = "XYZ"; pb["LeftArm"].rotation_euler = (0.9, 0, 0)
		pb["LeftForeArm"].rotation_mode = "XYZ"; pb["LeftForeArm"].rotation_euler = (1.2, 0, 0)
		pb["RightUpLeg"].rotation_mode = "XYZ"; pb["RightUpLeg"].rotation_euler = (-0.8, 0, 0)
		pb["RightLeg"].rotation_mode = "XYZ"; pb["RightLeg"].rotation_euler = (1.0, 0, 0)
		views = [("pose", (2.6, -3.0, 1.2), (0, 0, 0.92), 50)]
	if os.environ.get("ANIMSHOW") == "1":                             # кадры клипов: клип, секунда
		sc.render.resolution_x, sc.render.resolution_y = 500, 700
		sc.cycles.samples = 16
		views = []
		for cl, t in (("Sleep", 0.2), ("StandUp", 1.0), ("Stretch", 1.4), ("WashFace", 6.5), ("Walk", 0.3), ("Run", 0.2), ("SitIdle", 1.0), ("SitPhoneRead", 0.4), ("ClimbDown", 0.6), ("LookAround", 3.0)):
			views.append(("anim_%s_%02d" % (cl, int(t * 10)), (3.0, -3.2, 1.4), (0, 0, 0.7), 40, cl, t))
	for vw in views:
		nm, pos, tgt, lens = vw[:4]
		if len(vw) > 4:
			act = bpy.data.actions[vw[4]]
			rig.animation_data.action = act
			for tr in rig.animation_data.nla_tracks:
				tr.mute = True
			sc.frame_set(int(round(vw[5] * 30)) + 1)
		cam.location = Vector(pos)
		cam.rotation_euler = (Vector(tgt) - cam.location).to_track_quat("-Z", "Y").to_euler()
		cam.data.lens = lens
		sc.render.filepath = os.path.join(OUT, "hero_%s.png" % nm)
		bpy.ops.render.render(write_still=True)
