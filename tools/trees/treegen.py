# Игровые деревья средней полосы: берёза, сосна, ель (+ подрост и сухостой).
# Ствол и скелетные ветви — трубки с корой; листва/хвоя — «веточки-карточки»: настоящая детальная
# ветка (листья, иглы) отрисовывается в Blender в текстуру с прозрачностью и картой нормалей.
# Запуск: /tmp/claude-0/blender/v/bin/python -I tools/trees/treegen.py <out_dir>
#   ONLY=birch,pine  — только эти породы;  SHOW=1 — рендер показа (игровые модели в Blender).
# Выход: <out>/<порода>_wood.glb, <out>/<порода>_leaf.glb (узлы = варианты), <out>/kinds_trees.json.
import bpy, math, random, sys, os, json, zlib
import numpy as np
from mathutils import Vector

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/trees/game"
ONLY = [s for s in os.environ.get("ONLY", "").split(",") if s]
SHOW = os.environ.get("SHOW", "1") == "1"
TEX = os.path.join(OUT, "tex")
os.makedirs(TEX, exist_ok=True)
UP = Vector((0, 0, 1))
rnd = random.Random(1)
npr = np.random.default_rng(1)

def R(a, b):
	return rnd.uniform(a, b)

def rand_dir():
	v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1)))
	return v.normalized() if v.length > 1e-6 else Vector((1, 0, 0))

def seed(s):
	global npr
	rnd.seed(s)
	npr = np.random.default_rng(s)

# =============== текстуры ===============
def fnoise(h, w, beta, ax=1.0, ay=1.0):
	n = npr.standard_normal((h, w))
	F = np.fft.fft2(n)
	fy = np.fft.fftfreq(h)[:, None] * ay
	fx = np.fft.fftfreq(w)[None, :] * ax
	f = np.sqrt(fx * fx + fy * fy)
	f[0, 0] = 1.0
	F /= f ** beta
	F[0, 0] = 0
	r = np.real(np.fft.ifft2(F))
	return (r - r.mean()) / (r.std() + 1e-9)

def save_img(name, rgb, alpha=None, noncolor=False, fmt="JPEG"):
	h, w = rgb.shape[:2]
	a = np.ones((h, w)) if alpha is None else alpha
	img = bpy.data.images.new(name, w, h, alpha=alpha is not None)
	if noncolor:
		img.colorspace_settings.name = "Non-Color"
	img.pixels.foreach_set(np.ascontiguousarray(np.dstack([np.clip(rgb, 0, 1), a]), dtype=np.float32).ravel())
	ext = "png" if fmt == "PNG" else "jpg"
	img.filepath_raw = os.path.join(TEX, name + "." + ext)
	img.file_format = fmt
	sc = bpy.context.scene
	sc.render.image_settings.quality = 88
	img.save()
	return img

def normal_from_height(hgt, k):
	gy, gx = np.gradient(hgt)
	n = np.dstack([-gx * k, -gy * k, np.ones_like(hgt)])
	n /= np.linalg.norm(n, axis=2, keepdims=True)
	return n * 0.5 + 0.5

def stamp(arr, val, cx, cy, ln, ht, wob):
	h, w = arr.shape
	x0 = int(cx - ln / 2)
	for i in range(int(ln)):
		t = i / max(ln - 1, 1)
		hh = ht * (math.sin(math.pi * t) ** 0.6) * (1 + wob * math.sin(i * 0.37 + cx))
		y0 = cy + wob * 2 * math.sin(i * 0.11 + cy)
		for j in range(int(-hh), int(hh) + 1):
			yy = int(y0 + j) % h
			xx = (x0 + i) % w
			arr[yy, xx] = max(arr[yy, xx], val * (1.0 - abs(j) / (hh + 1)))

# Кора: плитка 0.6 x 1.2 м, 512 x 1024 (0.85 px/мм)
BH, BW = 1024, 512

def bark_birch():
	h, w = BH, BW
	low = fnoise(h, w, 1.8)
	layers = fnoise(h, w, 1.3, ax=18.0)
	col = np.ones((h, w, 3)) * np.array([0.86, 0.85, 0.80])
	col += low[..., None] * 0.035 + layers[..., None] * 0.02 * np.array([1.0, 0.95, 0.9])
	dark = np.zeros((h, w))
	for _ in range(700):
		stamp(dark, R(0.55, 1.0), R(0, w), R(0, h), R(7, 40), R(0.6, 1.4), 0.15)
	for _ in range(22):
		stamp(dark, 1.0, R(0, w), R(0, h), R(45, 170), R(1.5, 4.5), 0.35)
	peel = fnoise(h, w, 1.6)
	pm = np.clip((peel - 2.1) * 3.0, 0, 1)
	col = col * (1 - pm[..., None]) + np.array([0.80, 0.66, 0.55]) * pm[..., None]
	col = col * (1 - dark[..., None]) + np.array([0.10, 0.09, 0.085]) * dark[..., None]
	return col, 0.6 + low * 0.04 + layers * 0.03 - dark * 0.45 + pm * 0.08

def bark_birch_base():
	h, w = BH, BW
	n = fnoise(h, w, 1.5, ay=4.0)
	n2 = fnoise(h, w, 1.8)
	crack = np.clip(1 - np.abs(n) / 0.35, 0, 1) ** 1.5
	plate = np.clip(0.5 + n2 * 0.3, 0, 1)
	gray = np.array([0.30, 0.29, 0.27]) * (1 - plate[..., None]) + np.array([0.58, 0.56, 0.52]) * plate[..., None]
	col = gray * (1 - crack[..., None]) + np.array([0.045, 0.04, 0.037]) * crack[..., None]
	return col, 0.7 - crack * 0.6 + n2 * 0.05

def bark_pine_low():
	"""Комель сосны: толстые серо-бурые плиты, глубокие трещины, рыжина в бороздах."""
	h, w = BH, BW
	n = fnoise(h, w, 1.4, ay=3.0)
	n2 = fnoise(h, w, 1.7)
	n3 = fnoise(h, w, 1.1, ax=4.0)
	crack = np.clip(1 - np.abs(n) / 0.3, 0, 1) ** 1.2
	sub = np.clip(1 - np.abs(n3) / 0.25, 0, 1) * 0.5           # поперечные трещинки плит
	plate = np.clip(0.5 + n2 * 0.25, 0, 1)
	pc = np.array([0.30, 0.24, 0.19]) * (1 - plate[..., None]) + np.array([0.48, 0.40, 0.32]) * plate[..., None]
	deep = np.array([0.32, 0.12, 0.05])
	k = np.maximum(crack, sub)
	col = pc * (1 - k[..., None]) + deep * k[..., None]
	col *= (1 - crack[..., None] * 0.55)
	return col, 0.75 - crack * 0.6 - sub * 0.25 + n2 * 0.05

def bark_pine_up():
	"""Верх сосны: рыже-оранжевая тонкая шелушащаяся кора."""
	h, w = BH, BW
	n = fnoise(h, w, 1.6, ax=2.5)
	n2 = fnoise(h, w, 1.0)
	col = np.ones((h, w, 3)) * np.array([0.78, 0.42, 0.20])
	col += n[..., None] * 0.05 * np.array([1.0, 0.8, 0.5])
	flake = np.clip((n2 - 1.3) * 2.5, 0, 1)
	col = col * (1 - flake[..., None]) + np.array([0.90, 0.66, 0.46]) * flake[..., None]
	lines = np.zeros((h, w))
	for _ in range(160):
		stamp(lines, R(0.3, 0.7), R(0, w), R(0, h), R(10, 60), R(0.5, 1.2), 0.3)
	col = col * (1 - lines[..., None]) + np.array([0.35, 0.16, 0.08]) * lines[..., None]
	return col, 0.6 + n * 0.05 + flake * 0.1 - lines * 0.3

def bark_spruce():
	"""Ель: серо-бурая кора мелкими округлыми чешуйками."""
	h, w = BH, BW
	n = fnoise(h, w, 0.9)
	n2 = fnoise(h, w, 1.8)
	sc = np.clip(1 - np.abs(fnoise(h, w, 1.2, ay=1.4)) / 0.25, 0, 1)
	col = np.ones((h, w, 3)) * np.array([0.36, 0.29, 0.24])
	col += n2[..., None] * 0.04
	col += (n[..., None] > 1.2) * 0.06 * np.array([1.0, 0.85, 0.7])
	col *= (1 - sc[..., None] * 0.45)
	return col, 0.6 + n * 0.04 + n2 * 0.03 - sc * 0.3

def bark_dead():
	"""Сухостой: серебристая древесина без коры, продольные трещины, клочья коры."""
	h, w = BH, BW
	grain = fnoise(h, w, 1.2, ay=12.0)
	n2 = fnoise(h, w, 1.8)
	col = np.ones((h, w, 3)) * np.array([0.58, 0.55, 0.50])
	col += grain[..., None] * 0.05 + n2[..., None] * 0.04
	crack = np.clip(1 - np.abs(fnoise(h, w, 1.3, ay=10.0)) / 0.08, 0, 1)
	col *= (1 - crack[..., None] * 0.7)
	bark = np.clip((n2 - 1.0) * 2, 0, 1)
	col = col * (1 - bark[..., None]) + np.array([0.24, 0.19, 0.15]) * bark[..., None]
	return col, 0.6 + grain * 0.04 - crack * 0.4 + bark * 0.15

def bark_twig():
	h, w = BH // 2, BW // 2
	n = fnoise(h, w, 1.2, ay=3.0)
	col = np.ones((h, w, 3)) * np.array([0.16, 0.10, 0.075]) + n[..., None] * 0.02
	return col, 0.5 + n * 0.05

BARKS = {}

def bark_mat(name, gen):
	if name in BARKS:
		return BARKS[name]
	col, hgt = gen()
	ci = save_img(name, col)
	ni = save_img(name + "_n", normal_from_height(hgt, 6.0), noncolor=True)
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	b = nt.nodes["Principled BSDF"]
	b.inputs["Roughness"].default_value = 0.85
	t = nt.nodes.new("ShaderNodeTexImage"); t.image = ci
	nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
	tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = ni
	nm = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
	nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
	m["flat"] = col.reshape(-1, 3).mean(0).tolist()
	BARKS[name] = m
	return m

def leaf_atlas_birch():
	S = 256
	out = np.zeros((S * 2, S * 2, 4))
	greens = [(0.30, 0.45, 0.13), (0.26, 0.41, 0.11), (0.34, 0.48, 0.15), (0.31, 0.43, 0.14)]
	vv, uu = np.meshgrid((np.arange(S) + 0.5) / S, (np.arange(S) + 0.5) / S, indexing="ij")
	px = 1.25 / S
	for c in range(4):
		ci, cj = c % 2, c // 2
		k = 0.92 + 0.08 * c / 3
		x = vv * 1.25 - 0.25
		y = (uu - 0.5) + 0.03 * (c - 1.5) * np.clip(x, 0, 1) ** 2
		xb = np.clip(x, 0, 1)
		wv = np.where(xb < 0.22, 0.40 * k * (xb / 0.22) ** 0.5, 0.40 * k * ((1 - xb) / 0.78) ** 1.2)
		teeth = (((x * (15 + c)) % 1.0) ** 2) * 0.075 + (((x * (43 + 2 * c)) % 1.0) ** 2) * 0.03
		wt = wv * (1 - teeth * (x > 0.08))
		a_blade = np.clip((wt - np.abs(y)) / px + 0.5, 0, 1) * ((x >= 0) & (x <= 1))
		a_pet = np.clip((0.013 - np.abs(y)) / px + 0.5, 0, 1) * ((x < 0.02) & (x > -0.22))
		a = np.maximum(a_blade, a_pet)
		g = np.array(greens[c])
		col = np.ones((S, S, 3)) * g
		mid = np.exp(-np.abs(y) / 0.012)
		vein = np.exp(-(((x - np.abs(y) * 1.15) * 9.0 + 0.5) % 1.0 - 0.5) ** 2 / 0.003) * (np.abs(y) < wt * 0.9)
		edge = np.clip(1 - (wt - np.abs(y)) / (wt * 0.25 + 1e-4), 0, 1)
		col += (mid * 0.10 + vein * 0.045)[..., None] * np.array([0.9, 1.0, 0.5])
		col *= (1 - edge * 0.18)[..., None]
		col = np.where((a_pet > a_blade)[..., None], np.array([0.45, 0.40, 0.17]), col)
		col = np.where((a > 0.01)[..., None], col, g)
		out[cj * S:(cj + 1) * S, ci * S:(ci + 1) * S, :3] = col
		out[cj * S:(cj + 1) * S, ci * S:(ci + 1) * S, 3] = a
	return out

# =============== геометрия ===============
class Mesh:
	def __init__(s):
		s.v, s.f, s.uv, s.fm, s.col, s.nrm = [], [], [], [], [], []

	def build(s, name, mats):
		me = bpy.data.meshes.new(name)
		me.from_pydata(s.v, [], s.f)
		me.uv_layers.new(name="UVMap").data.foreach_set("uv", np.array(s.uv, dtype=np.float32).ravel())
		me.polygons.foreach_set("material_index", s.fm)
		me.polygons.foreach_set("use_smooth", [True] * len(s.f))
		for m in mats:
			me.materials.append(m)
		if s.col:
			ca = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
			ca.data.foreach_set("color", np.array(s.col, dtype=np.float32).ravel())
			me.color_attributes.active_color = ca
		if s.nrm:
			me.normals_split_custom_set_from_vertices(s.nrm)
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob

	def tris(s):
		return sum(len(f) - 2 for f in s.f)

TILE_W, TILE_H = 0.6, 1.2

def tube(M, pts, rads, sides, matf, aof, cap=False):
	"""matf(p, r, ang) -> индекс материала грани; aof(p) -> затенение 0..1."""
	n = len(pts)
	T = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
	N = T[0].orthogonal().normalized()
	C = 2 * math.pi * rads[0]
	rep = max(1, round(C / TILE_W))
	vs = 1.0 / (TILE_H * (C / rep) / TILE_W)
	base = len(M.v)
	ss = [0.0]
	for i in range(1, n):
		ss.append(ss[-1] + (pts[i] - pts[i - 1]).length)
	for i in range(n):
		if i > 0:
			N = T[i - 1].rotation_difference(T[i]) @ N
			N = (N - T[i] * N.dot(T[i])).normalized()
		B = T[i].cross(N)
		for j in range(sides + 1):
			a = 2 * math.pi * j / sides
			p = pts[i] + (N * math.cos(a) + B * math.sin(a)) * rads[i]
			M.v.append(tuple(p))
			ao = aof(p)
			M.col.append((ao, ao, ao, 1.0))
	for i in range(n - 1):
		pc = (pts[i] + pts[i + 1]) * 0.5
		for j in range(sides):
			a = base + i * (sides + 1) + j
			b = a + sides + 1
			M.f.append((a, a + 1, b + 1, b))
			M.fm.append(matf(pc, rads[i], 2 * math.pi * (j + 0.5) / sides))
			u0, u1 = j / sides * rep, (j + 1) / sides * rep
			M.uv += [(u0, ss[i] * vs), (u1, ss[i] * vs), (u1, ss[i + 1] * vs), (u0, ss[i + 1] * vs)]

def grow(p0, d0, L, r0, r1, seg, bendf, wander):
	"""bendf(t) -> вектор изгиба на метр (тропизмы)."""
	pts, rads = [p0.copy()], [r0]
	d, p = d0.normalized(), p0.copy()
	st = L / seg
	for k in range(1, seg + 1):
		t = k / seg
		d = (d + (bendf(t) + rand_dir() * wander) * st).normalized()
		p = p + d * st
		pts.append(p.copy())
		rads.append(r0 + (r1 - r0) * t ** 0.8)
	return pts, rads

def sample(pts, rads, t):
	f = min(max(t, 0.0), 1.0) * (len(pts) - 1)
	i = min(int(f), len(pts) - 2)
	u = f - i
	return pts[i].lerp(pts[i + 1], u), (pts[i + 1] - pts[i]).normalized(), rads[i] + (rads[i + 1] - rads[i]) * u

def side_dir(dp, sign, lift):
	perp = dp.cross(UP)
	if perp.length < 1e-3:
		perp = dp.cross(Vector((1, 0, 0)))
	perp.normalize()
	ortho = perp.cross(dp).normalized()
	if ortho.z < 0:
		ortho = -ortho
	return (perp * sign * math.cos(lift) + ortho * math.sin(lift)).normalized()

def card(M, p, xdir, roll, size, tw, crown, mat=0):
	"""Карточка-веточка: якорь текстуры в точке p, ось X карточки вдоль xdir, roll — наклон плоскости
	(0 — вертикальная, 90° — горизонтальная). size — длина по X, м. tw — данные текстуры веточки."""
	X = xdir.normalized()
	Z = UP - X * UP.dot(X)
	Z = Z.normalized() if Z.length > 1e-3 else X.orthogonal().normalized()
	Y = Z.cross(X)
	Zr = Z * math.cos(roll) + Y * math.sin(roll)
	nrm = X.cross(Zr).normalized()
	if nrm.z < 0:
		nrm = -nrm
	W = size
	H = size * tw["h"] / tw["w"]
	au, av = tw["au"], tw["av"]
	if rnd.random() < 0.5:                                          # зеркально — вдвое больше разнообразия
		uvs = [(1, 0), (0, 0), (0, 1), (1, 1)]
		au = 1 - au
	else:
		uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
	b = len(M.v)
	for (u, v) in [(0, 0), (1, 0), (1, 1), (0, 1)]:
		q = p + X * (u - au) * W + Zr * (v - av) * H
		M.v.append(tuple(q))
		c, rr = crown
		dv = Vector(((q.x - c.x) / rr.x, (q.y - c.y) / rr.y, (q.z - c.z) / rr.z))
		radial = Vector((dv.x / rr.x, dv.y / rr.y, dv.z / rr.z))
		radial = radial.normalized() if radial.length > 1e-4 else UP
		M.nrm.append(tuple((radial * 0.65 + nrm * 0.35 + UP * 0.25).normalized()))
		ao = 0.5 + 0.5 * min(1.0, dv.length) ** 1.3
		ao *= 0.85 + 0.15 * min(1.0, max(0.0, (q.z - c.z) / rr.z * 0.5 + 0.5))
		M.col.append((ao, ao, ao, 1.0))
	M.f.append((b, b + 1, b + 2, b + 3))
	M.fm.append(mat)
	M.uv += uvs

def crown_of(points):
	xs = [p.x for p in points]; ys = [p.y for p in points]; zs = [p.z for p in points]
	c = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2))
	r = Vector((max(0.3, (max(xs) - min(xs)) / 2), max(0.3, (max(ys) - min(ys)) / 2), max(0.3, (max(zs) - min(zs)) / 2)))
	return c, r

def ground_ao(z):
	return 0.55 + 0.45 * min(1.0, max(0.0, z / 1.6))

# =============== породы: каркас ===============
def trunk_line(H, r0, seg, lean, wander, flare=0.45):
	tp, tr = [], []
	d = Vector((lean, lean * 0.6, 1)).normalized()
	p = Vector((0, 0, -0.15))
	for k in range(seg + 1):
		t = k / seg
		r = r0 * (1 - t) ** 0.9 + 0.006
		if t < 0.05:
			r *= 1 + (0.05 - t) / 0.05 * flare
		tp.append(p.copy()); tr.append(r)
		d = (d + rand_dir() * wander).normalized()
		p = p + d * (H / seg)
	return tp, tr

def birch_frame(H):
	k = H / 17.0
	tp, tr = trunk_line(H, 0.155 * max(k, 0.25), max(8, int(16 * min(1, k * 1.5))), 0.015, 0.012)
	L1s, sprays, stubs = [], [], []
	n1 = max(8, int(56 * min(1.0, k ** 0.6)))
	az = R(0, 6.28)
	for i in range(n1):
		u = i / (n1 - 1)
		t = 0.24 + 0.73 * u
		q, dq, rq = sample(tp, tr, t)
		az += 2.40 + R(-0.35, 0.35)
		env = math.sin(math.pi * min(1.0, u * 0.92 + 0.07)) ** 0.7
		L1 = max(0.3 * k, (0.9 + 5.0 * env * (1 - 0.3 * u)) * R(0.8, 1.15) * k)
		pitch = math.radians(74 - 42 * u + R(-9, 9))
		d0 = Vector((math.sin(pitch) * math.cos(az), math.sin(pitch) * math.sin(az), math.cos(pitch)))
		r0 = min(rq * 0.62, (0.012 + 0.026 * L1 / 4.5) * max(k, 0.3))
		p1, r1 = grow(q - d0 * rq * 0.5, d0, L1, r0, 0.004, max(3, int(L1 / 0.8)),
			lambda t: UP * (0.45 * (1 - t) - 1.25 * t * t), 0.22)
		L1s.append((p1, r1))
		nsp = max(2, int(L1 / 0.3))
		for j in range(nsp):
			tb = 0.15 + 0.85 * j / nsp + R(-0.03, 0.03)
			q2, d2, _ = sample(p1, r1, tb)
			sd = side_dir(d2, 1 if j % 2 else -1, R(-0.4, 0.5))
			dd = (d2 * 0.55 + sd * 0.8 + Vector((0, 0, -0.35))).normalized()
			sz = min(1.5, max(0.45, (0.55 + 0.8 * (1 - tb)) * (0.3 * L1 / k + 0.5))) * min(1.0, 0.45 + k * 0.6) * R(0.85, 1.15)
			sprays.append((q2, dd, R(math.radians(10), math.radians(60)), sz))
		q3, d3, _ = sample(p1, r1, 1.0)
		sprays.append((q3, (d3 + Vector((0, 0, -0.5))).normalized(), R(0.2, 1.0), min(1.2, 0.5 + 0.12 * L1 / k) * min(1.0, 0.45 + k * 0.6)))
	for _ in range(int(7 * min(1, k))):
		q, dq, rq = sample(tp, tr, R(0.1, 0.26))
		a = R(0, 6.28)
		dd = Vector((math.cos(a), math.sin(a), R(-0.2, 0.4))).normalized()
		stubs.append(grow(q, dd, R(0.15, 0.5) * k, 0.012 * k + 0.004, 0.004, 2, lambda t: Vector(), 0.3))
	return tp, tr, L1s, sprays, stubs

def pine_frame(H, dead=False):
	k = H / 20.0
	tp, tr = trunk_line(H, 0.20 * max(k, 0.3), max(8, int(18 * min(1, k * 1.5))), 0.02, 0.02, 0.35)
	# у сосны верх ствола чуть изогнут
	L1s, sprays, stubs = [], [], []
	cs = R(0.55, 0.66) if k > 0.4 else 0.25
	n1 = max(8, int(40 * min(1.0, k ** 0.5)))
	az = R(0, 6.28)
	for i in range(n1):
		u = i / (n1 - 1)
		t = cs + (0.985 - cs) * u
		q, dq, rq = sample(tp, tr, t)
		az += 2.40 + R(-0.5, 0.5)
		env = (1 - u) ** 0.55 * 0.8 + 0.2
		L1 = max(0.35 * k, (0.6 + 3.4 * env) * R(0.6, 1.3) * k)
		pitch = math.radians(82 - 30 * u + R(-12, 12))
		d0 = Vector((math.sin(pitch) * math.cos(az), math.sin(pitch) * math.sin(az), math.cos(pitch)))
		r0 = min(rq * 0.6, (0.02 + 0.035 * L1 / 4.0) * max(k, 0.3))
		if dead:
			L1 *= R(0.15, 0.5)
		p1, r1 = grow(q - d0 * rq * 0.5, d0, L1, r0, 0.006, max(3, int(L1 / 0.55)),
			lambda t: UP * (0.35 * (1 - t) + 0.15) , 0.45)
		L1s.append((p1, r1))
		if dead:
			continue
		ks = min(1.0, 0.45 + k * 0.55)
		nsp = max(2, int(L1 / 0.22))
		for j in range(nsp):
			tb = 0.3 + 0.7 * j / nsp + R(-0.04, 0.04)
			q2, d2, _ = sample(p1, r1, tb)
			sd = side_dir(d2, 1 if j % 2 else -1, R(-0.3, 0.6))
			dd = (d2 * 0.6 + sd * 0.7 + UP * 0.3).normalized()
			sprays.append((q2, dd, R(math.radians(50), math.radians(100)), R(0.7, 1.05) * ks))
		q3, d3, _ = sample(p1, r1, 1.0)
		for _ in range(4):                                             # пучок-«облако» на конце ветви
			sprays.append((q3 - d3 * R(0.05, 0.3), (d3 + UP * 0.45 + rand_dir() * 0.45).normalized(), R(math.radians(40), math.radians(110)), R(0.7, 1.0) * ks))
	for _ in range(int(14 * min(1, k))):                              # сухие сучья по стволу ниже кроны
		q, dq, rq = sample(tp, tr, R(0.2, cs))
		a = R(0, 6.28)
		dd = Vector((math.cos(a), math.sin(a), R(-0.3, 0.2))).normalized()
		stubs.append(grow(q, dd, R(0.2, 0.9) * k, 0.015 * k + 0.004, 0.004, 2, lambda t: Vector(), 0.5))
	return tp, tr, L1s, sprays, stubs, cs

def spruce_frame(H, dead=False):
	k = H / 20.0
	tp, tr = trunk_line(H, 0.18 * max(k, 0.25), max(8, int(20 * min(1, k * 1.5))), 0.006, 0.006, 0.4)
	L1s, sprays, stubs = [], [], []
	z0 = 0.6 * k + 0.3
	step = 0.55 * max(k, 0.3)
	z = z0
	az = R(0, 6.28)
	while z < H - 0.4 * max(k, 0.3):
		t = z / H
		nwh = rnd.randint(3, 5)
		for w in range(nwh):
			a = az + w * 6.283 / nwh + R(-0.3, 0.3)
			q, dq, rq = sample(tp, tr, t)
			L1 = max(0.25 * k + 0.1, (H - z) * 0.27 * R(0.8, 1.1) + 0.15)
			if z < 2.0 * k and rnd.random() < 0.55:
				dead_b = True
			else:
				dead_b = dead
			pitch = math.radians(100 + 14 * (1 - t) - 50 * t ** 2 + R(-8, 8))
			d0 = Vector((math.sin(pitch) * math.cos(a), math.sin(pitch) * math.sin(a), math.cos(pitch)))
			r0 = min(rq * 0.55, (0.012 + 0.03 * L1 / 4.5) * max(k, 0.3))
			if dead_b:
				L1 *= R(0.2, 0.6)
			p1, r1 = grow(q - d0 * rq * 0.5, d0, L1, r0, 0.005, max(2, int(L1 / 0.7)),
				lambda t: UP * (-0.30 * (1 - t) + 0.75 * t * t), 0.15)
			L1s.append((p1, r1))
			if dead_b:
				continue
			nsp = max(1, int(L1 / 0.6))
			for j in range(nsp):
				tb = 0.25 + 0.75 * j / nsp + R(-0.03, 0.03)
				q2, d2, _ = sample(p1, r1, tb)
				sd = side_dir(d2, 1 if j % 2 else -1, 0.0)
				dd = (d2 * 0.75 + sd * 0.65).normalized()
				sz = min(1.25, 0.55 + 0.55 * (1 - tb) * min(1.0, L1 / 3.0)) * min(1.0, 0.4 + k * 0.6) * R(0.85, 1.1)
				sprays.append((q2, dd, R(math.radians(65), math.radians(100)), sz))
			q3, d3, _ = sample(p1, r1, 1.0)
			sprays.append((q3 - d3 * 0.15, d3, R(math.radians(70), math.radians(100)), min(1.1, 0.5 + 0.15 * L1) * min(1.0, 0.4 + k * 0.6)))
		az += R(0.4, 0.9)
		z += step * R(0.85, 1.15)
	if not dead:                                                      # верхушка — «свечка»
		q, dq, _ = sample(tp, tr, 0.97)
		for _ in range(3):
			sprays.append((q, (UP * 1.5 + rand_dir() * 0.4).normalized(), R(0.0, 3.14), 0.55 * min(1.0, 0.4 + k * 0.6)))
	return tp, tr, L1s, sprays, stubs

# =============== веточки (детально) -> текстура карточки ===============
def flat_y(M, k):
	M.v = [(x, y * k, z) for (x, y, z) in M.v]

def to_card_plane(M, k):
	"""Ветка росла в горизонтальной плоскости XY — повернуть её в плоскость карточки XZ, толщину сжать."""
	M.v = [(x, z * k, y) for (x, y, z) in M.v]

def leaf_quad(M, p, d, n, s, cell, tint):
	w = d.cross(n).normalized()
	L, W = 1.25 * s, s
	fold = n * 0.07 * W
	tipd = -n * 0.10 * s
	b = len(M.v)
	M.v += [tuple(q) for q in (p - w * W / 2, p + fold, p + w * W / 2, p + d * L - w * W / 2 + tipd, p + d * L + fold + tipd, p + d * L + w * W / 2 + tipd)]
	ci, cj = cell % 2, cell // 2
	U = lambda uu, vv: ((ci + uu) / 2, (cj + vv) / 2)
	M.f += [(b, b + 1, b + 4, b + 3), (b + 1, b + 2, b + 5, b + 4)]
	M.fm += [1, 1]
	M.uv += [U(0, 0), U(0.5, 0), U(0.5, 1), U(0, 1), U(0.5, 0), U(1, 0), U(1, 1), U(0.5, 1)]
	M.col += [tint] * 6

def needle(M, p, d, ln, wd, col):
	side = d.cross(rand_dir()).normalized() * wd / 2
	b = len(M.v)
	M.v += [tuple(p - side), tuple(p + side), tuple(p + d * ln)]
	M.f.append((b, b + 1, b + 2))
	M.fm.append(2)
	M.uv += [(0, 0), (1, 0), (0.5, 1)]
	tip = tuple(c * 1.15 for c in col)
	M.col += [col + (1,), col + (1,), tip + (1,)]

def twig_tube(M, pts, rads, sides, colr):
	tube(M, pts, rads, sides, lambda p, r, a: 0, lambda p: 1.0)
	for i in range(len(M.col) - len(pts) * (sides + 1), len(M.col)):
		M.col[i] = colr + (1.0,)

def twig_birch():
	M = Mesh()
	seed(101)
	L = 1.0
	p2, r2 = grow(Vector((0, 0, 0)), Vector((1, 0, -0.1)), L, 0.006, 0.0018, 8, lambda t: UP * (0.2 * (1 - t) - 1.2 * t * t), 0.4)
	twig_tube(M, p2, r2, 5, (0.10, 0.065, 0.05))
	for k in range(int(L * 0.45 / 0.05)):
		q, d, _ = sample(p2, r2, 0.55 + 0.45 * k / 9)
		_birch_leaf(M, q, d)
	k3 = int(L / 0.055)
	for m in range(k3):
		q3, d3, rr3 = sample(p2, r2, 0.08 + 0.9 * m / k3)
		sd = side_dir(d3, 1 if m % 2 else -1, R(-0.3, 0.3))
		dd = (d3 * 0.6 + sd * 0.8).normalized()
		L3 = R(0.25, 0.6) * (1.0 - 0.35 * m / k3)
		p3, r3 = grow(q3, dd, L3, min(rr3 * 0.7, 0.0024), 0.0011, 5, lambda t: UP * (-7.0 * t), 0.8)
		twig_tube(M, p3, r3, 3, (0.11, 0.07, 0.05))
		nl = int(L3 / 0.034)
		for z in range(nl):
			q4, d4, _ = sample(p3, r3, 0.12 + 0.88 * z / max(1, nl))
			_birch_leaf(M, q4, d4)
			if rnd.random() < 0.55:
				_birch_leaf(M, q4, d4)
	flat_y(M, 0.3)
	return M

def _birch_leaf(M, p, td):
	s = R(0.045, 0.066)
	side = side_dir(td, 1 if rnd.random() < 0.5 else -1, R(-0.6, 0.6))
	d = (td * 0.35 + side * 0.75 + Vector((0, 0, -0.45)) + rand_dir() * 0.35).normalized()
	n = (Vector((0, -1, 0)) * 0.8 + UP * 0.3 + rand_dir() * 0.5)
	n = (n - d * n.dot(d)).normalized()
	t = 1.0 if rnd.random() < 0.025 else R(0.82, 1.0)
	leaf_quad(M, p, d, n, s, rnd.randrange(4), (t, t, t, 1.0) if t < 1 else (1.6, 1.25, 0.25, 1.0))

def twig_pine():
	"""Побег сосны: иглы парами 4–7 см, серо-зелёные, пучками на концах побегов."""
	M = Mesh()
	seed(202)
	shoots = []
	p0, r0 = grow(Vector((0, 0, 0)), Vector((1, 0, 0.05)), 0.6, 0.007, 0.004, 6, lambda t: Vector(), 0.2)
	shoots.append((p0, r0, 0.25))
	for j in range(6):
		q, d, rr = sample(p0, r0, 0.3 + 0.11 * j)
		sd = side_dir(d, 1 if j % 2 else -1, R(-0.3, 0.3))
		dd = (d * 0.55 + sd * 0.8).normalized()
		ps, rs = grow(q, dd, R(0.16, 0.28) * (1.1 - 0.08 * j), rr * 0.75, 0.003, 4, lambda t: Vector(), 0.35)
		shoots.append((ps, rs, 0.1))
	for ps, rs, st in shoots:
		twig_tube(M, ps, rs, 4, (0.30, 0.17, 0.09))
		Ls = sum((ps[i + 1] - ps[i]).length for i in range(len(ps) - 1))
		n = int(Ls * (1 - st) / 0.0028)
		for i in range(n):
			t = st + (1 - st) * i / n
			q, d, rr = sample(ps, rs, t)
			for _ in range(2):
				a = rand_dir()
				nd = (d * 0.5 + (a - d * a.dot(d)).normalized() * 0.9).normalized()
				g = R(0.8, 1.12)
				needle(M, q, nd, R(0.05, 0.075), 0.0042, (0.13 * g, 0.22 * g, 0.12 * g))
		q, d, _ = sample(ps, rs, 1.0)                                  # почка на конце
		twig_tube(M, [q, q + d * 0.015], [0.005, 0.0015], 4, (0.45, 0.25, 0.12))
	to_card_plane(M, 0.4)
	return M

def twig_spruce():
	"""Лапа ели: плоская, веточки в стороны, короткая тёмная хвоя вокруг побегов."""
	M = Mesh()
	seed(303)
	p0, r0 = grow(Vector((0, 0, 0)), Vector((1, 0, 0)), 1.0, 0.008, 0.002, 10, lambda t: UP * 0.05, 0.12)
	shoots = [(p0, r0)]
	nb = 16
	for j in range(nb):
		t = 0.06 + 0.9 * j / nb
		q, d, rr = sample(p0, r0, t)
		sd = side_dir(d, 1 if j % 2 else -1, R(-0.15, 0.15))
		dd = (d * 0.55 + sd * 0.85).normalized()
		Lb = (0.36 * (1 - t) + 0.08) * R(0.85, 1.15)
		ps, rs = grow(q, dd, Lb, rr * 0.6, 0.0015, 5, lambda t: Vector((0, 0, -0.3)), 0.2)
		shoots.append((ps, rs))
		for m in range(int(Lb / 0.06)):
			q2, d2, rr2 = sample(ps, rs, 0.2 + 0.8 * m / max(1, int(Lb / 0.06)))
			sd2 = side_dir(d2, 1 if m % 2 else -1, R(-0.2, 0.2))
			L2 = R(0.04, 0.11) * (1 - 0.5 * m / max(1, int(Lb / 0.06)))
			ps2, rs2 = grow(q2, (d2 * 0.5 + sd2 * 0.85).normalized(), L2, 0.0015, 0.001, 2, lambda t: Vector(), 0.2)
			shoots.append((ps2, rs2))
	for ps, rs in shoots:
		twig_tube(M, ps, rs, 3, (0.16, 0.10, 0.06))
		Ls = sum((ps[i + 1] - ps[i]).length for i in range(len(ps) - 1))
		n = int(Ls / 0.0011)
		for i in range(n):
			q, d, _ = sample(ps, rs, i / max(1, n))
			a = rand_dir()
			nd = (d * 0.45 + (a - d * a.dot(d)).normalized() * 0.9).normalized()
			g = R(0.8, 1.12)
			young = 1.6 if (i > n * 0.9 and rnd.random() < 0.6) else 1.0      # светлые молодые приросты
			needle(M, q, nd, R(0.024, 0.036), 0.0048, (0.055 * g * young, 0.12 * g * young, 0.05 * g * young))
	to_card_plane(M, 0.25)
	return M

LEAF_IMG = {}

def capture(name, M, res):
	"""Ортокамера сбоку (-Y): альбедо без света + карта нормалей. Возвращает размеры и якорь."""
	sc = bpy.context.scene
	for o in list(sc.collection.objects):
		bpy.data.objects.remove(o)
	sp_at = getattr(M, "atlas", "birch")
	if sp_at not in LEAF_IMG:
		la = leaf_atlas_birch() if sp_at == "birch" else leaf_atlas(**BROAD_P[sp_at]["leaf"])
		LEAF_IMG[sp_at] = save_img(sp_at + "_leaf_atlas", la[..., :3], la[..., 3], fmt="PNG")
	atlas = LEAF_IMG[sp_at]
	xs = [v[0] for v in M.v]; zs = [v[2] for v in M.v]
	bw, bh = max(xs) - min(xs), max(zs) - min(zs)
	RX = res[0]
	RY = int(min(res[0], max(128, round(RX * bh / bw / 32) * 32)))
	W = max(bw, bh * RX / RY) * 1.04
	H = W * RY / RX
	cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
	result = {}
	for mode in ("albedo", "normal"):
		mats = []
		for idx in range(3):
			m = bpy.data.materials.new("cap_%s_%d" % (mode, idx))
			m.use_nodes = True
			nt = m.node_tree; N = nt.nodes; L = nt.links
			N.clear()
			out = N.new("ShaderNodeOutputMaterial")
			em = N.new("ShaderNodeEmission")
			mix = N.new("ShaderNodeMixShader")
			tp = N.new("ShaderNodeBsdfTransparent")
			L.new(tp.outputs[0], mix.inputs[1]); L.new(em.outputs[0], mix.inputs[2])
			L.new(mix.outputs[0], out.inputs[0])
			attr = N.new("ShaderNodeAttribute"); attr.attribute_name = "Color"
			if idx == 1:
				tx = N.new("ShaderNodeTexImage"); tx.image = atlas; tx.interpolation = "Closest"
				L.new(tx.outputs["Alpha"], mix.inputs[0])
				if mode == "albedo":
					mul = N.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
					mul.inputs["Factor"].default_value = 1.0
					L.new(tx.outputs["Color"], mul.inputs[6]); L.new(attr.outputs["Color"], mul.inputs[7])
					L.new(mul.outputs[2], em.inputs["Color"])
			else:
				mix.inputs[0].default_value = 1.0
				if mode == "albedo":
					L.new(attr.outputs["Color"], em.inputs["Color"])
			if mode == "normal":
				geo = N.new("ShaderNodeNewGeometry")
				# нормаль к камере: если смотрит от камеры — перевернуть
				fl = N.new("ShaderNodeMath"); fl.operation = "MULTIPLY_ADD"
				L.new(geo.outputs["Backfacing"], fl.inputs[0]); fl.inputs[1].default_value = -2.0; fl.inputs[2].default_value = 1.0
				sv = N.new("ShaderNodeVectorMath"); sv.operation = "SCALE"
				L.new(geo.outputs["Normal"], sv.inputs[0]); L.new(fl.outputs[0], sv.inputs["Scale"])
				sp = N.new("ShaderNodeSeparateXYZ"); L.new(sv.outputs[0], sp.inputs[0])
				ny = N.new("ShaderNodeMath"); ny.operation = "MULTIPLY"; ny.inputs[1].default_value = -1.0
				L.new(sp.outputs["Y"], ny.inputs[0])
				cb = N.new("ShaderNodeCombineXYZ")
				L.new(sp.outputs["X"], cb.inputs["X"]); L.new(sp.outputs["Z"], cb.inputs["Y"]); L.new(ny.outputs[0], cb.inputs["Z"])
				enc = N.new("ShaderNodeVectorMath"); enc.operation = "MULTIPLY_ADD"
				L.new(cb.outputs[0], enc.inputs[0]); enc.inputs[1].default_value = (0.5, 0.5, 0.5); enc.inputs[2].default_value = (0.5, 0.5, 0.5)
				L.new(enc.outputs[0], em.inputs["Color"])
			mats.append(m)
		ob = M.build("cap_" + name + mode, mats)
		sc.render.engine = "CYCLES"
		sc.cycles.device = "CPU"
		sc.cycles.samples = 24
		sc.cycles.use_denoising = False
		sc.cycles.transparent_max_bounces = 64
		sc.cycles.max_bounces = 0
		sc.cycles.filter_width = 1.0
		sc.render.film_transparent = True
		sc.view_settings.view_transform = "Standard"
		sc.view_settings.look = "None"
		sc.render.dither_intensity = 0
		sc.render.image_settings.file_format = "PNG"
		sc.render.image_settings.color_mode = "RGBA"
		sc.render.image_settings.color_depth = "8"
		sc.render.resolution_x, sc.render.resolution_y = RX, RY
		sc.render.resolution_percentage = 100
		if sc.world is None:
			sc.world = bpy.data.worlds.new("w")
		sc.world.use_nodes = True
		sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
		cd = bpy.data.cameras.new("capcam"); cd.type = "ORTHO"; cd.ortho_scale = W
		co = bpy.data.objects.new("capcam", cd); sc.collection.objects.link(co)
		co.location = (cx, -5, cz)
		co.rotation_euler = Vector((0, 1, 0)).to_track_quat("-Z", "Y").to_euler()
		sc.camera = co
		path = os.path.join(TEX, "_cap_%s_%s.png" % (name, mode))
		sc.render.filepath = path
		bpy.ops.render.render(write_still=True)
		img = bpy.data.images.load(path)
		px = np.array(img.pixels[:], dtype=np.float32).reshape(RY, RX, 4)
		result[mode] = px
		bpy.data.objects.remove(ob); bpy.data.objects.remove(co)
	alb = result["albedo"]
	a = alb[..., 3]
	rgb = alb[..., :3].copy()
	nrm = result["normal"][..., :3].copy()
	# нормали записаны как цвет через sRGB-вид: вернуть в линейные значения
	nrm = np.where(nrm <= 0.04045, nrm / 12.92, ((nrm + 0.055) / 1.055) ** 2.4)
	rgb, nrm = dilate(rgb, nrm, a)
	alb_img = save_img(name, rgb, a, fmt="PNG")
	n_img = save_img(name + "_n", nrm, noncolor=True)
	return {"w": W, "h": H, "au": (0 - (cx - W / 2)) / W, "av": (0 - (cz - H / 2)) / H, "img": alb_img, "nimg": n_img}

def dilate(rgb, nrm, a, it=24):
	"""Цвет листвы растекается в прозрачные области (без тёмной каймы на мипах)."""
	m = (a > 0.5).astype(np.float32)
	r, n = rgb * m[..., None], nrm * m[..., None]
	for _ in range(it):
		acc = np.zeros_like(r); accn = np.zeros_like(n); cnt = np.zeros_like(m)
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			acc += np.roll(r, (dy, dx), (0, 1)); accn += np.roll(n, (dy, dx), (0, 1)); cnt += np.roll(m, (dy, dx), (0, 1))
		new = (m == 0) & (cnt > 0)
		r[new] = acc[new] / cnt[new][:, None]
		n[new] = accn[new] / cnt[new][:, None]
		m = np.maximum(m, new.astype(np.float32))
	rest = m == 0
	if rest.any():
		r[rest] = rgb[a > 0.5].mean(0) if (a > 0.5).any() else np.array([0.2, 0.3, 0.1])
	flat = np.ones_like(nrm) * np.array([0.5, 0.5, 1.0])
	return r, np.where((a > 0.5)[..., None], nrm, flat)

def card_mat(name, tw):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	b = nt.nodes["Principled BSDF"]
	b.inputs["Roughness"].default_value = 0.8
	t = nt.nodes.new("ShaderNodeTexImage"); t.image = tw["img"]
	nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
	nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
	tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = tw["nimg"]
	nm = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
	nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
	return m

exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "broadleaf.py"), encoding="utf-8").read())   # осина, дуб, ольха, ива, яблоня

# =============== сборка игровых моделей ===============
def build_tree(sp, var, H, tw, mats, dead=False):
	"""Возвращает (wood Mesh, leaf Mesh, высота)."""
	seed(zlib.crc32((sp + var).encode()))
	W, Lf = Mesh(), Mesh()
	if sp == "birch":
		tp, tr, L1s, sprays, stubs = birch_frame(H)
		def matf(p, r, a):
			if r < 0.02:
				return 2
			edge = 1.1 + 0.6 * math.sin(3 * a + p.z * 2.1) + 0.35 * math.sin(7 * a)
			return 1 if p.z < edge * min(1.0, H / 12) else 0
	elif sp == "pine":
		tp, tr, L1s, sprays, stubs, cs = pine_frame(H, dead)
		def matf(p, r, a):
			if dead:
				return 0
			if r < 0.025:
				return 1
			edge = H * (0.42 + 0.06 * math.sin(2 * a + p.z * 1.3))
			return 1 if p.z > edge else 0
	elif sp == "spruce":
		tp, tr, L1s, sprays, stubs = spruce_frame(H, dead)
		def matf(p, r, a):
			return 0
	else:
		trunks, L1s, sprays, stubs = broad_frame(sp, H)
		tp, tr = trunks[0]
		L1s = trunks[1:] + L1s
		has_base = BROAD_P[sp]["base"]
		ntw = len(mats) - 1
		def matf(p, r, a):
			if r < 0.02:
				return ntw
			if has_base:
				edge = 1.0 + 0.5 * math.sin(3 * a + p.z * 2.1) + 0.3 * math.sin(7 * a)
				return 1 if p.z < edge * min(1.0, H / 12) else 0
			return 0
	pts = [q for (q, _, _, _) in sprays] or [p for p in tp]
	if sprays:
		cr = crown_of(pts)
	else:
		cr = crown_of(tp)
	def aof(p):
		c, rr = cr
		dv = Vector(((p.x - c.x) / rr.x, (p.y - c.y) / rr.y, (p.z - c.z) / rr.z)).length
		return ground_ao(p.z) * (0.55 + 0.45 * min(1.0, dv))
	ts = 10 if H > 6 else 6
	tube(W, tp, tr, ts, matf, aof)
	for (p1, r1) in L1s:
		if r1[0] < 0.011 and (sp in BROAD_P):
			continue                                                   # тонкие веточки скрыты листвой
		tube(W, p1, r1, 6 if r1[0] > 0.08 else (4 if r1[0] > 0.02 else 3), matf, aof)
	for (p1, r1) in stubs:
		tube(W, p1, r1, 3, lambda p, r, a: (len(mats) - 1 if (sp == "birch" or sp in BROAD_P) else 0), aof)
	Lf.crown = cr
	for (q, d, roll, sz) in sprays:
		card(Lf, q, d, roll, sz, tw, cr)
		if sp != "spruce":                                             # у ели лапы горизонтальны — сверху и так видны
			card(Lf, q, d, roll + math.radians(R(70, 110)), sz * R(0.85, 1.0), tw, cr)   # крест-накрест: не видно «ребром»
	return W, Lf, max(v[2] for v in W.v)

SPECIES = {
	# порода: (варианты [(имя, высота, сухостой)], разрешение карточки, кора)
	"birch": ([("birch_a", 17.0, False), ("birch_b", 15.0, False), ("birch_c", 19.0, False), ("birch_sap_a", 3.5, False), ("birch_sap_b", 5.5, False)],
		(512, 512), [("bark_birch", bark_birch), ("bark_birch_base", bark_birch_base), ("bark_twig", bark_twig)], twig_birch),
	"pine": ([("pine_a", 22.0, False), ("pine_b", 19.0, False), ("pine_c", 24.0, False), ("pine_sap_a", 2.2, False), ("pine_sap_b", 4.0, False), ("pine_dead_a", 15.0, True)],
		(512, 512), [("bark_pine_low", bark_pine_low), ("bark_pine_up", bark_pine_up)], twig_pine),
	"spruce": ([("spruce_a", 21.0, False), ("spruce_b", 17.0, False), ("spruce_c", 24.0, False), ("spruce_sap_a", 1.6, False), ("spruce_sap_b", 3.2, False), ("spruce_dead_a", 14.0, True)],
		(512, 512), [("bark_spruce", bark_spruce)], twig_spruce),
	"aspen": ([("aspen_a", 20.0, False), ("aspen_b", 17.0, False), ("aspen_sap_a", 4.0, False)],
		(512, 512), [("bark_aspen", bark_aspen), ("bark_aspen_base", bark_aspen_base), ("bark_twig", bark_twig)], lambda: twig_broad("aspen")),
	"oak": ([("oak_a", 18.0, False), ("oak_b", 15.0, False), ("oak_c", 21.0, False), ("oak_sap_a", 4.5, False)],
		(512, 512), [("bark_oak", bark_oak), ("bark_twig", bark_twig)], lambda: twig_broad("oak")),
	"alder": ([("alder_a", 16.0, False), ("alder_b", 13.0, False)],
		(512, 512), [("bark_alder", bark_alder), ("bark_twig", bark_twig)], lambda: twig_broad("alder")),
	"willow": ([("willow_a", 12.0, False), ("willow_b", 10.0, False)],
		(512, 512), [("bark_willow", bark_willow), ("bark_twig", bark_twig)], lambda: twig_broad("willow")),
	"apple": ([("apple_a", 5.5, False), ("apple_b", 4.5, False), ("apple_c", 6.5, False)],
		(512, 512), [("bark_apple", bark_apple), ("bark_twig", bark_twig)], lambda: twig_broad("apple")),
}

def export(objs, path):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format="AUTO",
		export_tangents=True, export_vertex_color="ACTIVE", export_apply=False)

def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	kinds = {}
	stats = []
	for sp, (vars_, res, barks, twigf) in SPECIES.items():
		if ONLY and sp not in ONLY:
			continue
		M = twigf()
		tw = capture(sp + "_twig", M, res)
		bmats = [bark_mat(n, g) for (n, g) in barks]
		if sp == "pine" or sp == "spruce":
			dmat = bark_mat("bark_dead", bark_dead)
		cm = card_mat(sp + "_twig", tw)
		woods, leaves = [], []
		for (vn, H, dead) in vars_:
			Wm, Lm, top = build_tree(sp, vn, H, tw, bmats, dead)
			wo = Wm.build(vn, [dmat] if dead else bmats)
			woods.append(wo)
			if Lm.f:
				leaves.append(Lm.build(vn + "_l", [cm]))
			cat = "dead" if dead else ("sapling" if (H < 6 and sp != "apple") else "tree")
			kinds[vn] = {"m": sp, "n": vn, "h": round(top, 2), "sc": 1.0, "cat": cat, "yaw": 0, "wood_only": dead}
			if Lm.f:
				c, rr = Lm.crown
				kinds[vn]["crown"] = [round(c.z / top, 3), round(rr.z / top, 3), round(max(rr.x, rr.y) * 0.85, 2), 1 if sp in ("pine", "spruce") else 0]
			stats.append("%s: %.1f м, кора %d тр., карточек %d" % (vn, top, Wm.tris(), len(Lm.f)))
		export(woods, os.path.join(OUT, sp + "_wood.glb"))
		for o in woods:
			o.name = o.name + "_w"
		for o in leaves:
			o.name = o.name[:-2]
		if leaves:
			export(leaves, os.path.join(OUT, sp + "_leaf.glb"))
		for o in woods + leaves:
			o.hide_render = True
		print("SPECIES", sp, "done", flush=True)
	for s in stats:
		print("STAT", s, flush=True)
	json.dump(kinds, open(os.path.join(OUT, "kinds_trees.json"), "w"), ensure_ascii=False, indent=0)

main()
