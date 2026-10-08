# Новые места (этап 10): АЗС и кафе, железная дорога (рельсы, вагоны, переезд, платформа), корпус лагеря/санатория,
# свалка, обломки вертолёта. Строится теми же средствами, что дома (house.py: HB, mat, фото-текстуры).
import zlib, bpy, math, random, sys, os
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import house as H
from house import HB, mat, house, text_mesh, W
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "cars"))
import car as C                                  # материалы машин (диски, шины, краска) и кузов для вертолёта

H.FLAT.update({"rail": ((0.32, 0.26, 0.22), 0.5, 0.8), "sleeper": ((0.30, 0.25, 0.20), 0.9, 0.0), "ballast": ((0.42, 0.40, 0.37), 1.0, 0.0),
	"wagon_red": ((1.0, 1.0, 1.0), 0.7, 0.2), "station_red": ((0.75, 0.12, 0.10), 0.5, 0.2),
	"scorch": ((0.28, 0.16, 0.09), 1.0, 0.0)})

def rail_seg(name):
	"""Путь 6 м: балласт, шпалы, два рельса (колея 1520)."""
	hb = HB()
	L = 6.0
	hb.poly(mat("ballast"), [(-L / 2, -1.6, 0.0), (-L / 2, 1.6, 0.0), (-L / 2, 1.1, 0.35), (-L / 2, -1.1, 0.35)], (L, 0, 0), (1, 1, 1))
	for i in range(10):
		hb.box(mat("sleeper"), (-L / 2 + (i + 0.5) * L / 10, 0, 0.42), (0.24, 2.7, 0.15), (1, 1, 1))
	for sy in (-0.8, 0.8):
		hb.box(mat("rail"), (0, sy, 0.57), (L, 0.07, 0.15), (1, 1, 1))
	return hb.build(name), None

def wagon(name, kind, col):
	"""Грузовой вагон 14 м: крытый (box) или цистерна (tank); тележки, сцепки."""
	hb = HB()
	L = 14.0
	for x in (-L / 2 + 2.0, L / 2 - 2.0):                             # тележки
		hb.box(mat("frame"), (x, 0, 0.95), (2.6, 2.0, 0.5))
		for dx in (-0.9, 0.9):
			for sy in (-0.8, 0.8):
				hb.cyl(mat("rim"), (x + dx, sy, 1.02), 0.45, 0.12, "Y", 14, col=(0.35, 0.3, 0.28))
	hb.box(mat("frame"), (0, 0, 1.45), (L, 2.8, 0.3))
	for sx in (-1, 1):
		hb.box(mat("metal"), (sx * (L / 2 + 0.2), 0, 1.4), (0.4, 0.25, 0.25))
	if kind == "box":
		hb.box(mat("wagon_red"), (0, 0, 2.95), (L, 3.0, 2.7), col)
		hb.cyl(mat("wagon_red"), (0, 0, 4.3), 1.5, L, "X", 16, col=col)
		for sy in (-1, 1):
			hb.box(mat("frame"), (0, sy * 1.51, 2.8), (3.2, 0.03, 2.3), (0.6, 0.6, 0.6))   # раздвижная дверь
		text_mesh(hb, "spray", "ЗАРАЖЕНО", 0.4, (-4.0, -1.53, 3.2), (0.85, 0.85, 0.82))
	else:
		hb.cyl(mat("wagon_red"), (0, 0, 2.95), 1.45, L - 0.6, "X", 20, col=col)
		hb.box(mat("frame"), (0, 0, 4.45), (1.2, 1.2, 0.3), (0.5, 0.5, 0.5))
	return hb.build(name), None

def crossing(name):
	"""Ж/д переезд: шлагбаумы (поднят/опущен), знак-крест, будка дежурного."""
	hb = HB()
	for sy, ang in ((-1, 0.0), (1, 1.2)):
		hb.box(mat("concrete"), (0, sy * 4.2, 0.6), (0.3, 0.3, 1.2), (0.8, 0.8, 0.8))
		bx = Vector((0, sy * 4.2, 1.15))
		d = Vector((0, -sy * math.cos(ang), math.sin(ang)))
		for k in range(6):
			c = bx + d * (0.35 + k * 0.6)
			hb.beam(mat("frame_white"), tuple(c - d * 0.3), tuple(c + d * 0.3), 0.08, col=(0.85, 0.1, 0.08) if k % 2 else (0.95, 0.95, 0.92))
	for sy in (-1, 1):                                                  # знак «Андреевский крест»
		p = Vector((1.5, sy * 5.0, 0))
		hb.cyl(mat("metal_paint"), (p.x, p.y, 1.2), 0.04, 2.4, "Z", 8, col=(0.6, 0.6, 0.6))
		for a in (0.7, -0.7):
			hb.box(mat("frame_white"), (p.x, p.y, 2.2), (0.04, 1.1, 0.16), (0.95, 0.95, 0.92), rot=(a, 0, 0))
	hb.box(mat("planks_blue"), (2.5, 6.0, 1.3), (2.0, 2.0, 2.6), (1, 1, 1))
	hb.box(mat("profnastil"), (2.5, 6.0, 2.7), (2.4, 2.4, 0.1), (0.5, 0.5, 0.5))
	return hb.build(name), None

def platform(name):
	"""Платформа 24 м с навесом и скамейкой."""
	hb = HB()
	hb.box(mat("concrete"), (0, 0, 0.55), (24.0, 3.5, 1.1), (0.8, 0.8, 0.78))
	for x in (-3.0, 3.0):
		hb.box(mat("metal_paint"), (x, 0.8, 2.3), (0.12, 0.12, 2.4), (0.5, 0.5, 0.5))
	hb.box(mat("profnastil"), (0, 0.4, 3.55), (8.0, 2.6, 0.08), (0.45, 0.55, 0.65))
	hb.box(mat("frame_white"), (0, 1.0, 1.4), (3.0, 0.4, 0.08), (0.5, 0.35, 0.25))
	hb.box(mat("frame_white"), (6.0, 1.5, 2.6), (1.6, 0.06, 0.5), (0.12, 0.3, 0.65))
	text_mesh(hb, "spray", "о.п. 47 км", 0.22, (6.0, 1.46, 2.6), (0.95, 0.95, 0.92))
	return hb.build(name), None

def gas_station(name):
	"""АЗС: навес на 4 колоннах с подсветкой, 2 островка колонок, магазин с витриной, стела цен."""
	hb = HB()
	hb.box(mat("concrete"), (0, 0, 0.05), (22.0, 16.0, 0.1), (0.75, 0.75, 0.73))               # площадка
	for x in (-5.0, 5.0):
		for y in (-3.0, 3.0):
			hb.box(mat("metal_paint"), (x, y, 2.6), (0.35, 0.35, 5.0), (0.85, 0.85, 0.85))
	hb.box(mat("metal_paint"), (0, 0, 5.3), (14.0, 9.0, 0.6), (0.85, 0.85, 0.85))              # навес
	hb.box(mat("frame_white"), (0, -4.51, 5.3), (14.0, 0.02, 0.5), (0.15, 0.45, 0.25))          # фриз
	hb.box(mat("frame_white"), (0, 4.51, 5.3), (14.0, 0.02, 0.5), (0.15, 0.45, 0.25))
	for y in (-1.5, 1.5):
		hb.box(mat("concrete"), (0, y, 0.2), (6.0, 1.0, 0.3), (0.85, 0.85, 0.85))
		for x in (-1.6, 1.6):
			hb.box(mat("metal_paint"), (x, y, 1.1), (0.6, 0.5, 1.6), (0.9, 0.9, 0.9))
			hb.box(mat("dark"), (x, y - 0.26, 1.4), (0.4, 0.02, 0.3))
	# магазин
	sh, shr = house("_gs_shop", dict(L=10.0, D=7.0, wall="plaster_white", t=0.3, h=3.2, plinth=0.2, roof="hip", rmat="profnastil", rcol=(0.5, 0.5, 0.5), pitch=8,
		inner="paint_wall", floor="linoleum", front=W(-2.5, 0.5, 3.5, w=2.4, h=2.2), back=[], left=W(0.0, w=1.2, h=1.2), right=[], door=(-4.3, 1.4), door_kind="metal",
		pvc=True, frame="frame_white", sill=0.4, state="broken", extras=["ac"], lining=True), 7)
	# стела
	hb.box(mat("metal_paint"), (9.5, -6.5, 3.0), (1.2, 0.4, 6.0), (0.15, 0.45, 0.25))
	for k in range(4):
		hb.box(mat("dark"), (9.5, -6.71, 4.8 - k * 0.8), (0.9, 0.02, 0.55))
	text_mesh(hb, "spray", "АЗС", 0.45, (9.5, -6.72, 5.65), (0.95, 0.95, 0.92))
	ob = hb.build(name)
	sh.location = (2.0, 10.0, 0.0)
	shr.location = (2.0, 10.0, 0.0)
	ob = _join(ob, sh, name)
	return _join(ob, shr, name), None

def cafe(name):
	ob, rf = house(name, dict(L=9.0, D=7.0, wall="planks_brown", t=0.25, h=3.0, plinth=0.4, roof="gable", rmat="profnastil", rcol=(0.62, 0.48, 0.40), pitch=22,
		inner="paint_wall", floor="linoleum", front=W(-2.5, 0.5, 2.8, w=1.8, h=1.6), back=W(0.0, w=1.2, h=1.2), left=W(0.0, w=1.2, h=1.2), right=W(0.0, w=1.2, h=1.2),
		door=(-3.6, 1.0), porch=dict(w=3.0, d=1.6, roof=True), pvc=True, frame="frame_white", state="broken"), 9)
	hb = HB()
	hb.box(mat("frame_white"), (0.5, -3.65, 3.9), (3.4, 0.08, 0.7), (0.65, 0.12, 0.1))
	text_mesh(hb, "spray", "КАФЕ", 0.5, (0.5, -3.7, 3.9), (0.95, 0.9, 0.7))
	sign = hb.build(name + "_sign", ao=False)
	return _join(ob, sign, name), rf

def corpus(name):
	"""Корпус детского лагеря/санатория: 2 этажа, 24×10 м, белая штукатурка, много окон."""
	xs = [-10.0 + i * 2.5 for i in range(9)]
	return house(name, dict(L=24.0, D=10.0, wall="plaster_old", t=0.4, h=3.0, floors=2, plinth=0.5, roof="gable", rmat="slate", rcol=(0.78, 0.74, 0.68), pitch=20,
		inner="paint_wall", icol=(0.85, 0.92, 0.95), floor="linoleum", front=[(x, 1.4, 1.5) for x in xs if abs(x) > 1], front2=[(x, 1.4, 1.5) for x in xs],
		back=[(x, 1.4, 1.5) for x in xs], left=W(-2.0, 2.0, w=1.4, h=1.5), right=W(-2.0, 2.0, w=1.4, h=1.5),
		door=(0.0, 1.6), porch=dict(w=4.0, d=2.4, roof=True, mat="concrete"), frame="frame_white", state="broken",
		rooms=[("x", 1.0, -11.6, 11.6, -6.0), ("y", -4.0, 1.0, 4.6, 2.5), ("y", 4.0, 1.0, 4.6, 2.5)], extras=["downpipe"]), 13)

def dump_pile(name, seed):
	"""Куча мусора: холм с обломками досок, шинами, бочками, мешками."""
	rnd = random.Random(seed)
	hb = HB()
	n = 10
	pts = [(math.cos(a) * 4.0 * rnd.uniform(0.8, 1.2), math.sin(a) * 3.0 * rnd.uniform(0.8, 1.2)) for a in [k * 2 * math.pi / n for k in range(n)]]
	bm = hb._bm(mat("ballast"))
	top = bm.verts.new((0, 0, 1.8))
	ring = [bm.verts.new((x, y, 0.0)) for (x, y) in pts]
	mid = [bm.verts.new((x * 0.55, y * 0.55, 1.1 + rnd.uniform(-0.2, 0.2))) for (x, y) in pts]
	fs = []
	for i in range(n):
		j = (i + 1) % n
		fs.append(bm.faces.new([ring[i], ring[j], mid[j], mid[i]]))
		fs.append(bm.faces.new([mid[i], mid[j], top]))
	hb._paint(bm, fs, (0.55, 0.48, 0.40))
	for _ in range(16):
		a = rnd.uniform(0, 6.28); r = rnd.uniform(0.5, 3.2)
		x, y = math.cos(a) * r, math.sin(a) * r * 0.75
		z = 1.8 * (1 - r / 4.0) + 0.1
		k = rnd.random()
		if k < 0.35:
			hb.box(mat("planks_brown"), (x, y, z), (rnd.uniform(1, 2.5), 0.15, 0.03), (0.8, 0.8, 0.8), rot=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.3, 0.3), rnd.uniform(0, 3)))
		elif k < 0.55:
			hb.cyl(mat("tire"), (x, y, z), 0.35, 0.22, "Y", 12, col=(1, 1, 1))
		elif k < 0.7:
			hb.cyl(mat("metal_paint"), (x, y, z + 0.3), 0.3, 0.9, "Z", 10, col=(0.35, 0.4, 0.3))
		else:
			hb.box(mat("fabric"), (x, y, z), (0.6, 0.5, 0.4), (0.15, 0.15, 0.17), rot=(0.2, 0.1, rnd.uniform(0, 3)))
	return hb.build(name), None

def heli_wreck(name):
	"""Обломки вертолёта (Ми-8-класса): фюзеляж на боку, хвостовая балка оторвана, лопасти разбросаны, копоть."""
	hb = HB(keep_winding=True)
	S = dict(L=11.5, W=2.5, top=[(0, 1.2), (0.05, 2.6), (0.15, 3.1), (0.75, 3.15), (0.88, 2.8), (0.96, 1.9), (1.0, 1.2)], clear=0.3, belt=1.8, tumble=0.18, sq=4.0,
		wheel_r=0.0, axles=(), glass=[(10.2, 11.4, "front"), (9.0, 10.8, "side")], lights={"head": (0, 0, 0, 0), "tail": (0, 0, 0, 0), "grille": (0, 0, 0, 0)}, broken=0.7)
	C.body(hb, S, (0.30, 0.34, 0.24), random.Random(5))
	G = (0.30, 0.34, 0.24)
	hb.box(mat("paint"), (7.3, 0, 3.45), (4.2, 1.7, 0.75), G)                      # кожух двигателей на крыше
	hb.box(mat("paint"), (5.0, 0, 3.35), (1.4, 1.3, 0.5), G)                       # редуктор
	hb.cyl(mat("frame"), (6.2, 0, 3.95), 0.32, 0.5, "Z", 10, col=(0.2, 0.2, 0.2))   # втулка несущего винта
	for sy in (-1, 1):
		hb.cyl(mat("frame"), (5.6, sy * 0.78, 3.55), 0.2, 0.9, "X", 8, col=(0.12, 0.11, 0.1))   # выхлопные патрубки (копоть)
		for k in range(5):                                                          # круглые окна грузовой кабины
			hb.cyl(mat("car_glass"), (2.6 + k * 1.15, sy * 1.27, 2.15), 0.22, 0.04, "Y", 10, col=(0.1, 0.12, 0.13))
		hb.box(mat("paint"), (0.2, sy * 0.95, 1.4), (1.6, 0.08, 2.0), G, rot=(0.0, 0.0, sy * 0.9))   # створки грузового люка распахнуты
	ob = C.finish(hb, name + "_f")
	ob.rotation_euler = (0.0, 0.0, 0.0)
	h2 = HB()
	h2.cyl(mat("paint"), (-4.5, 0.6, 1.4), 0.45, 8.0, "X", 12, r2=0.25, col=(0.30, 0.34, 0.24))       # хвостовая балка в стороне
	h2.box(mat("paint"), (-8.4, 0.6, 2.3), (1.2, 0.15, 1.8), (0.30, 0.34, 0.24))                     # киль
	h2.box(mat("paint"), (-7.6, 0.6, 1.5), (0.9, 1.8, 0.08), (0.30, 0.34, 0.24))                     # стабилизатор
	for k in range(3):                                                                               # хвостовой винт
		a = k * 2.09 + 0.4
		h2.box(mat("frame"), (-8.4 + math.cos(a) * 0.6, 0.85, 2.6 + math.sin(a) * 0.6), (1.2, 0.04, 0.16), (0.3, 0.3, 0.3), rot=(0.0, -a, 0.0))
	for (wx, wy) in ((9.5, -2.2), (3.0, 2.4), (2.4, 1.8)):                                         # колёса шасси отлетели
		h2.cyl(mat("tire"), (wx, wy, 0.28), 0.45, 0.3, "Z", 12, col=(0.05, 0.05, 0.05))
	for k in range(4):                                                  # лопасти
		a = k * 1.4 + 0.3
		h2.box(mat("frame"), (6.0 + math.cos(a) * 4.5, 3.0 + math.sin(a) * 3.0, 0.15), (7.5, 0.5, 0.06), (0.3, 0.3, 0.3), rot=(0.05, 0.03 * k, a))
	# выжженная земля: не плита 14×9 из soot (0.05 — чёрный квадрат), а несколько бурых пятен
	for (x, y, sx, sy) in ((1.5, 0.4, 2.8, 1.8), (5.2, -0.8, 2.2, 1.5), (7.4, 1.6, 1.8, 1.2)):
		h2.box(mat("scorch"), (x, y, 0.015), (sx, sy, 0.02), (0.55, 0.32, 0.18))
	o2 = h2.build(name + "_p")
	o2.location = (0, 0, 0)
	ob.location = (0, 0, 0)
	ob.rotation_euler = (0.25, 0.0, 0.0)                                # завалился на бок
	return _join(o2, ob, name), None

def rock_cave(name, seed):
	"""Скальный выход 12×9×5 м: несколько неровных глыб, вход в пещеру (вырезан цилиндром), мох сверху, тёмный зев."""
	import bmesh
	from mathutils import Matrix, noise
	rnd = random.Random(seed)
	bm = bmesh.new()
	for (x, y, z, sx, sy, sz) in ((0, 0.6, 2.0, 5.2, 4.0, 3.4), (3.8, 1.6, 1.5, 3.4, 3.0, 2.6), (-4.0, 0.8, 1.3, 3.2, 2.8, 2.2), (1.2, 3.0, 1.2, 3.0, 2.4, 2.0)):
		M = Matrix.Translation((x, y, z)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
		bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0, matrix=M)
	for v in bm.verts:
		n = noise.noise(v.co * 0.45 + Vector((seed, 0, 0))) * 0.9 + noise.noise(v.co * 1.3) * 0.3
		d = Vector((v.co.x, v.co.y, v.co.z - 1.0)).normalized()
		v.co += d * n
		if v.co.z < 0.0:
			v.co.z = v.co.z * 0.25 - 0.2                                # низ — в землю
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me); bm.free()
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	# вход в пещеру: вырезать цилиндр спереди (-Y)
	bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=1.35, depth=7.0, location=(0.3, -3.5, 1.15), rotation=(math.pi / 2, 0, 0))
	cut = bpy.context.active_object
	md = ob.modifiers.new("cave", "BOOLEAN")
	md.operation = "DIFFERENCE"
	md.object = cut
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.modifier_apply(modifier=md.name)
	bpy.data.objects.remove(cut)
	me = ob.data
	me.materials.append(mat("concrete"))
	me.materials.append(mat("dark"))
	bm = bmesh.new(); bm.from_mesh(me)
	cl = bm.loops.layers.color.new("Color")
	uv = bm.loops.layers.uv.new("UVMap")
	for f in bm.faces:
		c = f.calc_center_median()
		inside = abs(c.x - 0.3) < 1.5 and c.y > -2.6 and c.z < 2.4 and f.normal.y > -0.2   # стенки тоннеля
		f.material_index = 1 if inside else 0
		for l in f.loops:
			p = l.vert.co
			l[uv].uv = (p.x * 0.22 + p.z * 0.11, p.y * 0.22 + p.z * 0.17)
			g = 0.75 + 0.25 * noise.noise(p * 0.8) + 0.1 * noise.noise(p * 3.1)
			col = Vector((0.62, 0.60, 0.56)) * g
			if l.vert.normal.z > 0.75:                                  # мох и лишайник — пятнами на плоских верхах
				mk = min(1.0, (l.vert.normal.z - 0.75) * 3.0) * max(0.0, noise.noise(p * 0.6 + Vector((3, 1, 0))) + 0.3)
				col = col.lerp(Vector((0.30, 0.36, 0.20)), min(0.7, mk))
			if p.z < 0.6:
				col = col * (0.7 + 0.5 * p.z)                           # низ темнее
			if inside:
				col = Vector((0.08, 0.08, 0.08))
			l[cl] = (col.x, col.y, col.z, 1.0)
	bm.to_mesh(me); bm.free()
	me.color_attributes.active_color = me.color_attributes["Color"]
	for pl in me.polygons:
		pl.use_smooth = True
	return ob, None

# ---------------- общественные и придорожные здания: дом + вывеска над входом ----------------
def signed(name, spec, seed, text, size=0.5, board=(0.92, 0.92, 0.9), tcol=(0.12, 0.2, 0.55)):
	"""Здание по house() и вывеска на фасаде (-Y) над дверью."""
	ob, rf = house(name, spec, seed)
	L, D = spec["L"], spec["D"]
	H = spec["h"] * spec.get("floors", 1) + 0.3 * (spec.get("floors", 1) - 1) + spec.get("plinth", 0.5)
	bw = min(L * 0.8, len(text) * size * 0.72 + 0.8)
	dx = spec.get("sign_x", 0.0)
	hb = HB()
	hb.box(mat("frame_white"), (dx, -D / 2 - 0.08, H - 0.45), (bw, 0.08, size * 1.5), board)
	text_mesh(hb, "spray", text, size, (dx, -D / 2 - 0.13, H - 0.45), tcol)
	return _join(ob, hb.build(name + "_sign", ao=False), name), rf

def _row(x0, x1, step, w, h, skip=()):
	xs = []
	x = x0
	while x <= x1 + 1e-6:
		if all(abs(x - k) > 1.0 for k in skip):
			xs.append((x, w, h))
		x += step
	return xs

PUBLIC = {
	# школа: 2 этажа, белый кирпич, ленты окон
	"school": (dict(L=30.0, D=11.0, wall="brick_white", t=0.4, h=3.3, floors=2, plinth=0.6, plinth_mat="concrete", roof="gable", rmat="slate", rcol=(0.78, 0.74, 0.68), pitch=18,
		inner="paint_wall", icol=(0.75, 0.88, 0.85), floor="linoleum", front=_row(-13.0, 13.0, 2.6, 1.8, 1.8, skip=(0.0,)), front2=_row(-13.0, 13.0, 2.6, 1.8, 1.8),
		back=_row(-13.0, 13.0, 2.6, 1.8, 1.8), left=W(-2.5, 2.5, w=1.6, h=1.8), right=W(-2.5, 2.5, w=1.6, h=1.8), door=(0.0, 1.8),
		porch=dict(w=4.5, d=2.6, roof=True, mat="concrete"), frame="frame_white", state="broken", rooms=[("x", 1.2, -14.6, 14.6, -6.0), ("y", -6.0, 1.2, 5.1, 3.0), ("y", 6.0, 1.2, 5.1, 3.0)],
		extras=["downpipe"]), "ШКОЛА", 0.7),
	# администрация: 2 этажа, красный кирпич, вальма, флагшток у входа
	"admin": (dict(L=16.0, D=10.0, wall="brick_red", wcol=(1.0, 0.85, 0.78), t=0.4, h=3.1, floors=2, plinth=0.6, plinth_mat="concrete", roof="hip", rmat="profnastil", rcol=(0.30, 0.42, 0.36), pitch=20,
		inner="paint_wall", floor="linoleum", front=_row(-6.6, 6.6, 2.2, 1.4, 1.6, skip=(0.0,)), front2=_row(-6.6, 6.6, 2.2, 1.4, 1.6), back=_row(-6.6, 6.6, 2.2, 1.4, 1.6),
		left=W(-2.0, 2.0, w=1.4, h=1.6), right=W(-2.0, 2.0, w=1.4, h=1.6), door=(0.0, 1.4), door_kind="metal", porch=dict(w=3.6, d=2.2, roof=True, mat="concrete"),
		pvc=True, frame="frame_white", state="broken", rooms=[("x", 1.0, -7.6, 7.6, -1.0)], extras=["downpipe", "ac"]), "АДМИНИСТРАЦИЯ", 0.45),
	# ФАП: одноэтажный, белая штукатурка, зелёная кровля
	"fap": (dict(L=12.0, D=8.0, wall="plaster_white", t=0.35, h=2.9, plinth=0.5, plinth_mat="concrete", roof="gable", rmat="profnastil", rcol=(0.36, 0.62, 0.45), pitch=24,
		inner="paint_wall", icol=(0.92, 0.95, 0.95), floor="linoleum", front=W(-4.0, -2.0, 2.4, 4.4, w=1.3, h=1.5), back=W(-3.0, 0.0, 3.0, w=1.3, h=1.5), left=W(0.0, w=1.3, h=1.5),
		right=W(0.0, w=1.3, h=1.5), door=(0.4, 1.2), door_kind="metal", porch=dict(w=2.6, d=1.8, roof=True, mat="concrete"), pvc=True, frame="frame_white", state="broken",
		rooms=[("x", 0.8, -5.6, 5.6, 0.4)], extras=["downpipe"], sign_x=0.4), "ФАП", 0.6, (0.95, 0.95, 0.95), (0.7, 0.08, 0.06)),
	# пожарная часть: кирпич, высокие ворота, вышка-сушилка
	"fire_station": (dict(L=16.0, D=11.0, wall="brick_red", t=0.4, h=4.6, plinth=0.3, plinth_mat="concrete", roof="gable", rmat="profnastil", rcol=(0.55, 0.12, 0.10), pitch=16,
		inner="paint_wall", floor="linoleum", front=W(-6.5, 6.5, w=1.2, h=1.4), back=W(-4.0, 0.0, 4.0, w=1.4, h=1.4), left=W(0.0, w=1.4, h=1.4), right=W(0.0, w=1.4, h=1.4),
		door=(-2.2, 3.4), door_kind="metal", frame="frame_white", state="broken", rooms=[]), "ПОЖАРНАЯ ЧАСТЬ", 0.45, (0.92, 0.92, 0.9), (0.7, 0.08, 0.06)),
	# придорожное
	"supermarket": (dict(L=26.0, D=18.0, wall="plaster_white", t=0.3, h=4.6, plinth=0.2, plinth_mat="concrete", roof="gable", rmat="profnastil", rcol=(0.7, 0.72, 0.74), pitch=7,
		inner="paint_wall", floor="linoleum", front=_row(-11.0, 11.0, 2.4, 2.0, 2.8, skip=(-2.0,)), back=[], left=[], right=W(0.0, w=1.0, h=1.0), door=(-2.0, 2.4), door_kind="metal",
		porch=dict(w=8.0, d=3.0, roof=True, mat="concrete"), pvc=True, frame="frame_white", state="broken", rooms=[("x", 4.0, -12.6, 12.6, 8.0)], extras=["ac"], sign_x=-2.0),
		"ПРОДУКТЫ 24", 0.8, (0.85, 0.15, 0.10), (0.98, 0.95, 0.9)),
	"tire_shop": (dict(L=10.0, D=7.0, wall="planks_peel", wcol=(0.75, 0.78, 0.8), t=0.2, h=3.6, plinth=0.15, plinth_mat="concrete", roof="gable", rmat="tin_rust", rcol=(0.9, 0.9, 0.9), pitch=10,
		inner="paint_wall", floor="floor_wood", front=W(3.2, w=1.0, h=1.0), back=[], left=W(0.0, w=0.9, h=0.9), right=[], door=(-1.2, 3.0), door_kind="metal", frame="frame_white",
		state="broken", rooms=[], sign_x=-0.5), "ШИНОМОНТАЖ", 0.42, (0.98, 0.85, 0.15), (0.08, 0.08, 0.08)),
	"auto_service": (dict(L=15.0, D=10.0, wall="block", t=0.3, h=4.4, plinth=0.15, plinth_mat="concrete", roof="gable", rmat="profnastil", rcol=(0.30, 0.38, 0.55), pitch=10,
		inner="paint_wall", floor="linoleum", front=W(5.6, w=1.2, h=1.2), back=W(-4.0, 4.0, w=1.2, h=1.0), left=[], right=W(0.0, w=1.2, h=1.2), door=(-2.6, 3.4), door_kind="metal",
		frame="frame_white", state="broken", rooms=[("x", 3.0, -7.3, 7.3, 4.5)], sign_x=0.0), "АВТОСЕРВИС", 0.55, (0.15, 0.3, 0.6), (0.95, 0.95, 0.95)),
	"motel": (dict(L=18.0, D=10.0, wall="plaster_beige", t=0.35, h=2.9, floors=2, plinth=0.5, plinth_mat="concrete", roof="hip", rmat="profnastil", rcol=(0.55, 0.30, 0.22), pitch=22,
		inner="wallpaper", floor="linoleum", front=_row(-7.5, 7.5, 2.5, 1.3, 1.5, skip=(0.0,)), front2=_row(-7.5, 7.5, 2.5, 1.3, 1.5), back=_row(-7.5, 7.5, 2.5, 1.3, 1.5),
		left=W(-2.0, 2.0, w=1.3, h=1.5), right=W(-2.0, 2.0, w=1.3, h=1.5), door=(0.0, 1.4), door_kind="metal", porch=dict(w=3.4, d=2.0, roof=True, mat="concrete"),
		pvc=True, frame="frame_white", state="broken", rooms=[("x", 0.6, -8.6, 8.6, 0.0)], extras=["ac", "dish", "downpipe"]), "ГОСТИНИЦА", 0.55, (0.15, 0.25, 0.45), (0.95, 0.9, 0.7)),
	"dps_post": (dict(L=6.0, D=4.5, wall="plaster_white", t=0.25, h=2.8, plinth=0.4, plinth_mat="concrete", roof="hip", rmat="profnastil", rcol=(0.25, 0.32, 0.55), pitch=18,
		inner="paint_wall", floor="linoleum", front=W(-1.5, 1.5, w=1.4, h=1.4), back=W(0.0, w=1.2, h=1.2), left=W(0.0, w=1.2, h=1.2), right=[], door=(-2.3, 0.9), door_kind="metal",
		pvc=True, frame="frame_white", state="broken", rooms=[], sign_x=0.4), "ДПС", 0.55, (0.15, 0.3, 0.65), (0.95, 0.95, 0.95)),
}

def burnt(name, base, seed):
	"""Сгоревший дом: тот же дом без крыши (обгоревшие стропила), стены в копоти."""
	import house as Hm
	spec = dict(Hm.TYPES[base])
	spec["state"] = "ruin"
	ob, rf = house(name, spec, seed)
	for o in (ob, rf):
		cl = o.data.color_attributes["Color"]
		rnd = random.Random(seed)
		for i, d in enumerate(cl.data):
			c = d.color
			k = 0.22 + 0.25 * rnd.random()
			d.color = (c[0] * k, c[1] * k * 0.95, c[2] * k * 0.9, 1.0)
	# крыши почти нет: оставим только каркас — уберём 70% граней крыши
	import bmesh
	bm = bmesh.new(); bm.from_mesh(rf.data)
	rnd = random.Random(seed + 1)
	kill = [f for f in bm.faces if rnd.random() < 0.7]
	bmesh.ops.delete(bm, geom=kill, context="FACES")
	bm.to_mesh(rf.data); bm.free()
	return ob, rf

def _join(a, b, name):
	bpy.ops.object.select_all(action="DESELECT")
	a.select_set(True); b.select_set(True)
	bpy.context.view_layer.objects.active = a
	bpy.ops.object.join()
	o = bpy.context.view_layer.objects.active
	o.name = name
	return o

JOBS = {
	"rail_seg": lambda: rail_seg("rail_seg"),
	"wagon_box_red": lambda: wagon("wagon_box_red", "box", (0.45, 0.16, 0.10)),
	"wagon_box_green": lambda: wagon("wagon_box_green", "box", (0.25, 0.32, 0.25)),
	"wagon_tank": lambda: wagon("wagon_tank", "tank", (0.12, 0.12, 0.12)),
	"rail_crossing": lambda: crossing("rail_crossing"),
	"rail_platform": lambda: platform("rail_platform"),
	"gas_station": lambda: gas_station("gas_station"),
	"cafe": lambda: cafe("cafe"),
	"camp_corpus": lambda: corpus("camp_corpus"),
	"dump_pile_a": lambda: dump_pile("dump_pile_a", 1),
	"dump_pile_b": lambda: dump_pile("dump_pile_b", 2),
	"heli_wreck": lambda: heli_wreck("heli_wreck"),
	"rock_cave": lambda: rock_cave("rock_cave", 5),
	"house_izba_burnt": lambda: burnt("house_izba_burnt", "house_izba_a", 31),
	"house_brick_burnt": lambda: burnt("house_brick_burnt", "house_brick_small", 32),
}
for _k, _v in PUBLIC.items():
	JOBS[_k] = (lambda k=_k, v=_v: signed(k, v[0], zlib.crc32(k.encode()), *v[1:]))

if __name__ == "__main__":
	out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/houses/out"
	bpy.ops.wm.read_factory_settings(use_empty=True)
	objs = []
	only = [x for x in os.environ.get("ONLY", "").split(",") if x]
	i = 0
	for n, fn in JOBS.items():
		if only and n not in only:
			continue
		o, r = fn()
		o.location = ((i % 4) * 26.0, -(i // 4) * 22.0, 0)
		if r is not None:
			r.location = o.location
			objs.append(r)
		objs.append(o)
		i += 1
		print("PLACE %-16s %6d тр. %.1f x %.1f x %.1f" % (n, sum(len(p.vertices) - 2 for p in o.data.polygons), o.dimensions.x, o.dimensions.y, o.dimensions.z), flush=True)
	H.preview(objs, os.path.join(out, "places.png"), persp=True, pad=10.0, dist_k=0.8, elev=32)
