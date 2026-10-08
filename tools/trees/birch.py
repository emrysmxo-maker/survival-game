# Повислая берёза (Betula pendula) в Blender: ствол, ветви, свисающие прутья, листья.
# Запуск: /tmp/claude-0/blender/v/bin/python -I tools/trees/birch.py <out_dir> [<dl_dir>]
# out_dir: birch.blend, текстуры, рендеры. dl_dir: HDRI и трава Poly Haven (только для показа).
import bpy, math, random, sys, os
import numpy as np
from mathutils import Vector

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/trees"
DL = sys.argv[2] if len(sys.argv) > 2 else os.path.join(OUT, "dl")
RENDER = os.environ.get("RENDER", "all")      # all | none | a | b | c
SAMPLES = int(os.environ.get("SAMPLES", "96"))
SEED = int(os.environ.get("SEED", "7"))
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(SEED)
npr = np.random.default_rng(SEED)
UP = Vector((0, 0, 1))

def R(a, b):
	return rnd.uniform(a, b)

def rand_dir():
	v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1)))
	return v.normalized() if v.length > 1e-6 else Vector((1, 0, 0))

# ---------------- текстуры (numpy -> bpy image) ----------------
def fnoise(h, w, beta, ax=1.0, ay=1.0):
	"""Бесшовный шум 1/f^beta; ax/ay > 1 — вытягивает пятна поперёк этой оси."""
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

def to_image(name, rgba, noncolor=False):
	h, w = rgba.shape[:2]
	img = bpy.data.images.new(name, w, h, alpha=True)
	if noncolor:
		img.colorspace_settings.name = "Non-Color"
	img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).ravel())
	img.filepath_raw = os.path.join(OUT, "tex", name + ".png")
	img.file_format = "PNG"
	os.makedirs(os.path.join(OUT, "tex"), exist_ok=True)
	img.save()
	return img

def stamp(arr, mask_val, cx, cy, ln, ht, wobble):
	"""Тёмная горизонтальная чечевичка/трещина с рваным краем (с переносом через край)."""
	h, w = arr.shape
	x0 = int(cx - ln / 2)
	for i in range(int(ln)):
		t = i / max(ln - 1, 1)
		hh = ht * (math.sin(math.pi * t) ** 0.6) * (1 + wobble * math.sin(i * 0.37 + cx))
		y0 = cy + wobble * 2 * math.sin(i * 0.11 + cy)
		for j in range(int(-hh), int(hh) + 1):
			yy = int(y0 + j) % h
			xx = (x0 + i) % w
			k = 1.0 - abs(j) / (hh + 1)
			arr[yy, xx] = max(arr[yy, xx], mask_val * k)

def bark_white():
	"""Белая кора: плитка 0.6 x 1.2 м, 1024 x 2048 (1.7 px/мм)."""
	h, w = 2048, 1024
	base = np.array([0.86, 0.85, 0.80])
	low = fnoise(h, w, 1.8)
	layers = fnoise(h, w, 1.3, ax=18.0)      # слоистость бересты (длинное по горизонтали)
	col = np.ones((h, w, 3)) * base
	col += (low[..., None] * 0.035) * np.array([1.0, 1.0, 1.05])
	col += (layers[..., None] * 0.02) * np.array([1.0, 0.95, 0.9])
	dark = np.zeros((h, w))
	for _ in range(1400):                    # чечевички: короткие тёмные чёрточки
		stamp(dark, R(0.55, 1.0), R(0, w), R(0, h), R(14, 80), R(1.0, 2.6), 0.15)
	for _ in range(45):                      # крупные чёрные трещины-пояски
		stamp(dark, 1.0, R(0, w), R(0, h), R(90, 340), R(3.0, 9.0), 0.35)
	peel = fnoise(h, w, 1.6)
	pm = np.clip((peel - 2.1) * 3.0, 0, 1)   # отслоения бересты — розовато-рыжие
	col = col * (1 - pm[..., None]) + np.array([0.80, 0.66, 0.55]) * pm[..., None]
	edge = np.clip(1 - np.abs(peel - 2.1) * 8, 0, 1) * 0.35
	ink = np.array([0.10, 0.09, 0.085])
	col = col * (1 - dark[..., None]) + ink * dark[..., None]
	col *= (1 - edge[..., None] * 0.5)
	hgt = 0.6 + low * 0.04 + layers * 0.03 - dark * 0.45 + pm * 0.08 + edge * 0.2
	return col, hgt

def bark_base():
	"""Комель старой берёзы: чёрная трещиноватая кора с серыми плитками. 1024 x 1024, 0.6 x 0.6 м."""
	h, w = 1024, 1024
	n = fnoise(h, w, 1.5, ay=4.0)            # вытянуто по вертикали
	n2 = fnoise(h, w, 1.8)
	crack = np.clip(1 - np.abs(n) / 0.35, 0, 1) ** 1.5
	plate = np.clip(0.5 + n2 * 0.3, 0, 1)
	gray = np.array([0.33, 0.31, 0.29]) * (1 - plate[..., None]) + np.array([0.62, 0.60, 0.56]) * plate[..., None]
	col = gray * (1 - crack[..., None]) + np.array([0.045, 0.04, 0.037]) * crack[..., None]
	col *= (0.9 + 0.1 * fnoise(h, w, 0.8)[..., None] * 0.5)
	hgt = 0.7 - crack * 0.6 + n2 * 0.05
	return col, hgt

def leaf_atlas():
	"""4 листа берёзы 2x2 (по 512 px). В ячейке: поперёк u (y -0.5..0.5), вдоль v (x -0.25..1, 0 = основание пластинки)."""
	S = 512
	out = np.zeros((S * 2, S * 2, 4))
	greens = [(0.30, 0.45, 0.13), (0.26, 0.41, 0.11), (0.34, 0.48, 0.15), (0.31, 0.43, 0.14)]
	vv, uu = np.meshgrid((np.arange(S) + 0.5) / S, (np.arange(S) + 0.5) / S, indexing="ij")
	px = 1.25 / S
	for c in range(4):
		ci, cj = c % 2, c // 2
		k = 0.92 + 0.08 * c / 3
		x = vv * 1.25 - 0.25
		y = (uu - 0.5) + 0.03 * (c - 1.5) * np.clip(x, 0, 1) ** 2         # лёгкая асимметрия
		xb = np.clip(x, 0, 1)
		wv = np.where(xb < 0.22, 0.40 * k * (xb / 0.22) ** 0.5, 0.40 * k * ((1 - xb) / 0.78) ** 1.2)
		s1 = (x * (15 + c)) % 1.0
		s2 = (x * (43 + 2 * c)) % 1.0
		teeth = (s1 ** 2) * 0.075 + (s2 ** 2) * 0.03                     # двоякопильчатый край
		wt = wv * (1 - teeth * (x > 0.08))
		d_blade = (wt - np.abs(y)) / px                                    # расстояние до края, px
		a_blade = np.clip(d_blade + 0.5, 0, 1) * ((x >= 0) & (x <= 1))
		a_pet = np.clip((0.011 - np.abs(y)) / px + 0.5, 0, 1) * ((x < 0.02) & (x > -0.22))
		a = np.maximum(a_blade, a_pet)
		g = np.array(greens[c])
		col = np.ones((S, S, 3)) * g
		mid = np.exp(-np.abs(y) / 0.012)
		vein = np.exp(-(((x - np.abs(y) * 1.15) * 9.0 + 0.5) % 1.0 - 0.5) ** 2 / 0.003) * (np.abs(y) < wt * 0.9)
		edge = np.clip(1 - (wt - np.abs(y)) / (wt * 0.25 + 1e-4), 0, 1)
		col += (mid * 0.10 + vein * 0.045)[..., None] * np.array([0.9, 1.0, 0.5])
		col *= (1 - edge * 0.18)[..., None]
		col *= (0.96 + 0.04 * fnoise(S, S, 1.0)[..., None] * 0.6)
		col = np.where((a_pet > a_blade)[..., None], np.array([0.45, 0.40, 0.17]), col)
		col = np.where((a > 0.01)[..., None], col, g)                      # фон = цвет листа (без каймы в мипах)
		out[cj * S:(cj + 1) * S, ci * S:(ci + 1) * S, :3] = col
		out[cj * S:(cj + 1) * S, ci * S:(ci + 1) * S, 3] = a
	return out

def make_textures():
	cw, hw = bark_white()
	cb, hb = bark_base()
	im = {}
	im["bw"] = to_image("birch_bark", np.dstack([np.clip(cw, 0, 1), np.ones(hw.shape)]))
	im["bwh"] = to_image("birch_bark_h", np.dstack([np.repeat(np.clip(hw, 0, 1)[..., None], 3, 2), np.ones(hw.shape)]), True)
	im["bb"] = to_image("birch_base", np.dstack([np.clip(cb, 0, 1), np.ones(hb.shape)]))
	im["bbh"] = to_image("birch_base_h", np.dstack([np.repeat(np.clip(hb, 0, 1)[..., None], 3, 2), np.ones(hb.shape)]), True)
	im["leaf"] = to_image("birch_leaf", np.clip(leaf_atlas(), 0, 1))
	return im

# ---------------- геометрия ----------------
class Mesh:
	def __init__(s):
		s.v, s.f, s.uv, s.young, s.tint = [], [], [], [], []

	def build(s, name, attrs):
		me = bpy.data.meshes.new(name)
		me.from_pydata(s.v, [], s.f)
		uvl = me.uv_layers.new(name="UVMap")
		uvl.data.foreach_set("uv", np.array(s.uv, dtype=np.float32).ravel())
		for a in attrs:
			vals = getattr(s, a)
			at = me.attributes.new(a, "FLOAT", "POINT")
			at.data.foreach_set("value", np.array(vals, dtype=np.float32))
		me.validate()
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob

BARK = Mesh()
LEAF = Mesh()
TILE_W, TILE_H = 0.6, 1.2

def tube(pts, rads, sides):
	n = len(pts)
	T = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
	N = T[0].orthogonal().normalized()
	C = 2 * math.pi * rads[0]
	rep = max(1, round(C / TILE_W))
	vscale = 1.0 / (TILE_H * (C / rep) / TILE_W)
	base = len(BARK.v)
	s = 0.0
	for i in range(n):
		if i > 0:
			N = T[i - 1].rotation_difference(T[i]) @ N
			N = (N - T[i] * N.dot(T[i])).normalized()
			s += (pts[i] - pts[i - 1]).length
		B = T[i].cross(N)
		r = rads[i]
		yg = min(1.0, max(0.0, (0.03 - r) / 0.018))          # тонкие ветки — тёмно-бурые
		for j in range(sides + 1):
			a = 2 * math.pi * j / sides
			BARK.v.append(tuple(pts[i] + (N * math.cos(a) + B * math.sin(a)) * r))
			BARK.young.append(yg)
	for i in range(n - 1):
		for j in range(sides):
			a = base + i * (sides + 1) + j
			b = a + sides + 1
			BARK.f.append((a, a + 1, b + 1, b))
	# UV по петлям в том же порядке, что и грани
	for i in range(n - 1):
		s0 = sum((pts[k + 1] - pts[k]).length for k in range(i)) * vscale
		s1 = s0 + (pts[i + 1] - pts[i]).length * vscale
		for j in range(sides):
			u0, u1 = j / sides * rep, (j + 1) / sides * rep
			BARK.uv += [(u0, s0), (u1, s0), (u1, s1), (u0, s1)]

def grow(p0, d0, L, r0, r1, seg, up_k, down_k, wander, out=None, out_k=0.0):
	pts, rads = [p0.copy()], [r0]
	d, p = d0.normalized(), p0.copy()
	st = L / seg
	for k in range(1, seg + 1):
		t = k / seg
		bend = UP * (up_k * (1 - t) - down_k * t * t) + rand_dir() * wander
		if out is not None:
			bend += out * out_k
		d = (d + bend * st).normalized()
		p = p + d * st
		pts.append(p.copy())
		rads.append(r0 + (r1 - r0) * t ** 0.8)
	return pts, rads

def sample(pts, rads, t):
	f = t * (len(pts) - 1)
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

N_LEAF = [0]

def leaf(p, twig_d, centre):
	s = R(0.045, 0.068)
	side = side_dir(twig_d, 1 if rnd.random() < 0.5 else -1, R(-0.6, 0.6))
	d = (twig_d * 0.35 + side * 0.75 + Vector((0, 0, -0.45)) + rand_dir() * 0.35).normalized()
	outw = Vector((p.x - centre.x, p.y - centre.y, 0))
	outw = outw.normalized() if outw.length > 1e-3 else Vector((1, 0, 0))
	n = (UP * 0.8 + outw * 0.45 + rand_dir() * 0.55)
	n = (n - d * n.dot(d)).normalized()
	w = d.cross(n).normalized()
	L, W = 1.25 * s, 1.0 * s
	fold = n * 0.07 * W
	tipd = -n * 0.10 * s
	b = len(LEAF.v)
	pts = [p - w * W / 2, p + fold, p + w * W / 2,
		p + d * L - w * W / 2 + tipd, p + d * L + fold + tipd, p + d * L + w * W / 2 + tipd]
	LEAF.v += [tuple(q) for q in pts]
	c = rnd.randrange(4)
	ci, cj = c % 2, c // 2
	tint = 1.0 if rnd.random() < 0.025 else R(0.0, 0.35)      # ~2.5% листьев уже желтеют
	LEAF.tint += [tint] * 6
	LEAF.young += [0.0] * 6
	U = lambda uu, vv: ((ci + uu) / 2, (cj + vv) / 2)
	LEAF.f += [(b, b + 1, b + 4, b + 3), (b + 1, b + 2, b + 5, b + 4)]
	LEAF.uv += [U(0, 0), U(0.5, 0), U(0.5, 1), U(0, 1), U(0.5, 0), U(1, 0), U(1, 1), U(0.5, 1)]
	N_LEAF[0] += 1

def birch():
	H = 17.0
	# ствол: прямой, чуть «гуляет», комель расширен
	tp, tr = [], []
	d = Vector((0.015, 0.01, 1)).normalized()
	p = Vector((0, 0, -0.15))
	seg = 44
	for k in range(seg + 1):
		t = k / seg
		r = 0.155 * (1 - t) ** 0.9 + 0.006
		if t < 0.04:
			r *= 1 + (0.04 - t) / 0.04 * 0.45
		tp.append(p.copy())
		tr.append(r)
		d = (d + rand_dir() * 0.012 + Vector((0.004, 0, 0))).normalized()
		p = p + d * (H / seg)
	tube(tp, tr, 16)
	centre = Vector((0, 0, 0))
	# сухие сучки внизу ствола
	for _ in range(9):
		t = R(0.12, 0.3)
		q, dq, rq = sample(tp, tr, t)
		dd = side_dir(dq, 1, 0) if False else Vector((math.cos(R(0, 6.28)), math.sin(R(0, 6.28)), R(-0.2, 0.4))).normalized()
		pts, rads = grow(q, dd, R(0.15, 0.6), 0.012, 0.004, 3, 0, 0.5, 0.4)
		tube(pts, rads, 5)
	# скелетные ветви
	n1 = 68
	az = R(0, 6.28)
	for i in range(n1):
		u = i / (n1 - 1)
		t = 0.22 + 0.75 * u
		q, dq, rq = sample(tp, tr, t)
		az += 2.40 + R(-0.35, 0.35)
		env = math.sin(math.pi * min(1.0, u * 0.92 + 0.07)) ** 0.7
		L1 = max(0.6, (0.9 + 5.0 * env * (1 - 0.3 * u)) * R(0.8, 1.15))
		pitch = math.radians(74 - 42 * u + R(-9, 9))
		d0 = Vector((math.sin(pitch) * math.cos(az), math.sin(pitch) * math.sin(az), math.cos(pitch)))
		r0 = min(rq * 0.62, 0.012 + 0.026 * L1 / 4.5)
		p1, r1s = grow(q - d0 * rq * 0.5, d0, L1, r0, 0.004, max(5, int(L1 / 0.2)), 0.45, 1.25, 0.22)
		tube(p1, r1s, 7 if r0 > 0.025 else 5)
		# ветви 2-го порядка
		k2 = max(4, int(L1 / 0.23))
		for j in range(k2):
			tb = 0.12 + 0.86 * j / k2 + R(-0.02, 0.02)
			q2, d2, rr2 = sample(p1, r1s, tb)
			sd = side_dir(d2, 1 if j % 2 else -1, R(-0.5, 0.7))
			a = math.radians(R(38, 58))
			dd = (d2 * math.cos(a) + sd * math.sin(a)).normalized()
			L2 = min(2.0, max(0.3, (0.35 + 0.8 * (1 - tb)) * (0.45 * L1 + 0.35) * R(0.75, 1.2)))
			r20 = min(rr2 * 0.65, 0.0035 + 0.006 * L2)
			p2, r2s = grow(q2, dd, L2, r20, 0.0018, max(3, int(L2 / 0.14)), 0.15, 1.9, 0.55)
			tube(p2, r2s, 4)
			for k in range(int(L2 * 0.45 / 0.05)):                 # листья на конце ветки
				q3, d3, _ = sample(p2, r2s, 0.55 + 0.45 * k / max(1, int(L2 * 0.45 / 0.05)))
				leaf(q3, d3, centre)
			# свисающие прутья (3-й порядок) — главная примета повислой берёзы
			k3 = max(2, int(L2 / 0.12))
			for m in range(k3):
				tc = 0.1 + 0.88 * m / k3
				q3, d3, rr3 = sample(p2, r2s, tc)
				sd3 = side_dir(d3, 1 if m % 2 else -1, R(-0.4, 0.4))
				dd3 = (d3 * 0.6 + sd3 * 0.8).normalized()
				L3 = R(0.22, 0.6) * (1.15 - 0.35 * u)
				p3, r3s = grow(q3, dd3, L3, min(rr3 * 0.7, 0.0024), 0.0011, 4, 0.0, 4.5, 1.0)
				tube(p3, r3s, 3)
				nl = int(L3 / 0.045)
				for z in range(nl):
					q4, d4, _ = sample(p3, r3s, 0.12 + 0.88 * z / max(1, nl))
					leaf(q4, d4, centre)
					if rnd.random() < 0.35:
						leaf(q4, d4, centre)

# ---------------- материалы ----------------
def mat_bark(im):
	m = bpy.data.materials.new("birch_bark")
	m.use_nodes = True
	nt = m.node_tree
	N, L = nt.nodes, nt.links
	N.clear()
	out = N.new("ShaderNodeOutputMaterial")
	bs = N.new("ShaderNodeBsdfPrincipled")
	bs.inputs["Roughness"].default_value = 0.78
	uv = N.new("ShaderNodeUVMap")
	tw = N.new("ShaderNodeTexImage"); tw.image = im["bw"]
	th = N.new("ShaderNodeTexImage"); th.image = im["bwh"]
	mb = N.new("ShaderNodeMapping"); mb.inputs["Scale"].default_value = (1, 2, 1)   # плитка комля квадратная
	L.new(uv.outputs[0], mb.inputs[0])
	tb = N.new("ShaderNodeTexImage"); tb.image = im["bb"]
	tbh = N.new("ShaderNodeTexImage"); tbh.image = im["bbh"]
	for t in (tw, th):
		L.new(uv.outputs[0], t.inputs[0])
	for t in (tb, tbh):
		L.new(mb.outputs[0], t.inputs[0])
	# маска комля: высота + шум
	tc = N.new("ShaderNodeTexCoord")
	sep = N.new("ShaderNodeSeparateXYZ")
	L.new(tc.outputs["Object"], sep.inputs[0])
	nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 1.6
	L.new(tc.outputs["Object"], nz.inputs[0])
	add = N.new("ShaderNodeMath"); add.operation = "MULTIPLY_ADD"
	L.new(nz.outputs["Fac"], add.inputs[0]); add.inputs[1].default_value = 1.4
	L.new(sep.outputs["Z"], add.inputs[2])
	mr = N.new("ShaderNodeMapRange")
	L.new(add.outputs[0], mr.inputs["Value"])
	mr.inputs["From Min"].default_value = 1.0
	mr.inputs["From Max"].default_value = 2.9
	mr.inputs["To Min"].default_value = 1.0
	mr.inputs["To Max"].default_value = 0.0
	mc = N.new("ShaderNodeMix"); mc.data_type = "RGBA"
	L.new(mr.outputs[0], mc.inputs["Factor"])
	L.new(tw.outputs["Color"], mc.inputs[6]); L.new(tb.outputs["Color"], mc.inputs[7])
	# молодые ветки — тёмно-бурые с блеском
	at = N.new("ShaderNodeAttribute"); at.attribute_name = "young"
	my = N.new("ShaderNodeMix"); my.data_type = "RGBA"
	L.new(at.outputs["Fac"], my.inputs["Factor"])
	L.new(mc.outputs[2], my.inputs[6])
	my.inputs[7].default_value = (0.075, 0.045, 0.032, 1)
	L.new(my.outputs[2], bs.inputs["Base Color"])
	mh = N.new("ShaderNodeMix"); mh.data_type = "FLOAT"
	L.new(mr.outputs[0], mh.inputs["Factor"])
	L.new(th.outputs["Color"], mh.inputs[2]); L.new(tbh.outputs["Color"], mh.inputs[3])
	bump = N.new("ShaderNodeBump"); bump.inputs["Distance"].default_value = 0.006
	L.new(mh.outputs[0], bump.inputs["Height"])
	L.new(bump.outputs[0], bs.inputs["Normal"])
	L.new(bs.outputs[0], out.inputs[0])
	return m

def mat_leaf(im):
	m = bpy.data.materials.new("birch_leaf")
	m.use_nodes = True
	nt = m.node_tree
	N, L = nt.nodes, nt.links
	N.clear()
	out = N.new("ShaderNodeOutputMaterial")
	tex = N.new("ShaderNodeTexImage"); tex.image = im["leaf"]
	at = N.new("ShaderNodeAttribute"); at.attribute_name = "tint"
	yel = N.new("ShaderNodeMix"); yel.data_type = "RGBA"
	L.new(at.outputs["Fac"], yel.inputs["Factor"])
	L.new(tex.outputs["Color"], yel.inputs[6])
	yel.inputs[7].default_value = (0.55, 0.45, 0.06, 1)
	bs = N.new("ShaderNodeBsdfPrincipled")
	bs.inputs["Roughness"].default_value = 0.45
	L.new(yel.outputs[2], bs.inputs["Base Color"])
	tr = N.new("ShaderNodeBsdfTranslucent")
	gm = N.new("ShaderNodeMix"); gm.data_type = "RGBA"
	gm.inputs["Factor"].default_value = 0.0
	hs = N.new("ShaderNodeHueSaturation")
	hs.inputs["Saturation"].default_value = 1.25
	hs.inputs["Value"].default_value = 0.85
	L.new(yel.outputs[2], hs.inputs["Color"])
	L.new(hs.outputs[0], tr.inputs["Color"])
	mx = N.new("ShaderNodeMixShader"); mx.inputs[0].default_value = 0.32
	L.new(bs.outputs[0], mx.inputs[1]); L.new(tr.outputs[0], mx.inputs[2])
	tp = N.new("ShaderNodeBsdfTransparent")
	ma = N.new("ShaderNodeMixShader")
	L.new(tex.outputs["Alpha"], ma.inputs[0])
	L.new(tp.outputs[0], ma.inputs[1]); L.new(mx.outputs[0], ma.inputs[2])
	L.new(ma.outputs[0], out.inputs[0])
	return m

# ---------------- сцена для показа ----------------
def scene_setup():
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = SAMPLES
	sc.cycles.use_denoising = True
	sc.cycles.max_bounces = 6
	sc.cycles.transparent_max_bounces = 24
	sc.view_settings.view_transform = "AgX"
	sc.view_settings.look = "AgX - Medium High Contrast"
	w = bpy.data.worlds.new("w"); sc.world = w
	w.use_nodes = True
	N, L = w.node_tree.nodes, w.node_tree.links
	N.clear()
	hdr = os.path.join(DL, "kloofendal_48d_partly_cloudy_puresky_2k.hdr")
	bg = N.new("ShaderNodeBackground"); bg.inputs["Strength"].default_value = 0.7
	ev = N.new("ShaderNodeTexEnvironment"); ev.image = bpy.data.images.load(hdr)
	mp = N.new("ShaderNodeMapping"); tc = N.new("ShaderNodeTexCoord")
	mp.inputs["Rotation"].default_value = (0, 0, math.radians(110))
	L.new(tc.outputs["Generated"], mp.inputs[0]); L.new(mp.outputs[0], ev.inputs[0])
	L.new(ev.outputs[0], bg.inputs[0])
	o = N.new("ShaderNodeOutputWorld"); L.new(bg.outputs[0], o.inputs[0])
	# земля
	bpy.ops.mesh.primitive_plane_add(size=600)
	g = bpy.context.object
	gm = bpy.data.materials.new("ground"); gm.use_nodes = True
	N, L = gm.node_tree.nodes, gm.node_tree.links
	bs = N["Principled BSDF"]
	tc = N.new("ShaderNodeTexCoord"); mp = N.new("ShaderNodeMapping")
	mp.inputs["Scale"].default_value = (150, 150, 1)
	L.new(tc.outputs["UV"], mp.inputs[0])
	def tx(f, nc=False):
		t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(DL, f))
		if nc: t.image.colorspace_settings.name = "Non-Color"
		L.new(mp.outputs[0], t.inputs[0]); return t
	L.new(tx("aerial_grass_rock_diff_2k.jpg").outputs[0], bs.inputs["Base Color"])
	L.new(tx("aerial_grass_rock_rough_2k.jpg", True).outputs[0], bs.inputs["Roughness"])
	nm = N.new("ShaderNodeNormalMap")
	L.new(tx("aerial_grass_rock_nor_gl_2k.jpg", True).outputs[0], nm.inputs["Color"])
	L.new(nm.outputs[0], bs.inputs["Normal"])
	g.data.materials.append(gm)
	# человек-ориентир 1.8 м: серый столбик с головой (только для масштаба)
	bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=1.55, location=(2.2, -1.2, 0.775))
	h1 = bpy.context.object
	bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(2.2, -1.2, 1.68))
	h2 = bpy.context.object
	mm = bpy.data.materials.new("ref"); mm.use_nodes = True
	mm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.3, 0.25, 1)
	for o in (h1, h2):
		o.data.materials.append(mm)
	# солнце в сторону HDRI-солнца для чётких теней
	sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 2.4; sun.angle = math.radians(1.2)
	so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so)
	so.rotation_euler = (math.radians(50), 0, math.radians(200))

def cam(name, loc, look, lens=None, ortho=None, res=(1200, 1500)):
	sc = bpy.context.scene
	cd = bpy.data.cameras.new(name)
	if ortho:
		cd.type = "ORTHO"; cd.ortho_scale = ortho
	else:
		cd.lens = lens
	cd.clip_end = 500
	co = bpy.data.objects.new(name, cd); sc.collection.objects.link(co)
	co.location = loc
	co.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
	sc.camera = co
	sc.render.resolution_x, sc.render.resolution_y = res
	sc.render.resolution_percentage = int(os.environ.get("PCT", "100"))
	sc.render.filepath = os.path.join(OUT, name + ".png")
	bpy.ops.render.render(write_still=True)
	print("render", sc.render.filepath, flush=True)

def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	im = make_textures()
	birch()
	bark = BARK.build("birch_wood", ["young"])
	lv = LEAF.build("birch_leaf", ["tint", "young"])
	bark.data.materials.append(mat_bark(im))
	lv.data.materials.append(mat_leaf(im))
	for o in (bark, lv):
		o.data.shade_smooth() if hasattr(o.data, "shade_smooth") else None
	tb = sum(len(f) - 2 for f in BARK.f)
	tl = len(LEAF.f) * 2
	zs = [v[2] for v in BARK.v]
	xs = [v[0] for v in LEAF.v]; ys = [v[1] for v in LEAF.v]
	print("STAT высота %.1f м, крона %.1f x %.1f м, листьев %d, треугольников: кора %d, листья %d" % (
		max(zs), max(xs) - min(xs), max(ys) - min(ys), N_LEAF[0], tb, tl), flush=True)
	bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "birch.blend"))
	if RENDER == "none":
		return
	scene_setup()
	if RENDER in ("all", "a"):
		cam("birch_full", (17.0, -16.0, 1.7), (0, 0, 7.6), lens=24)
	if RENDER in ("all", "b"):
		cam("birch_close", (2.2, -2.6, 1.6), (0, 0, 2.2), lens=35, res=(1200, 1200))
	if RENDER in ("all", "c"):
		el = math.radians(46.8)
		d = Vector((math.cos(el) * math.cos(math.radians(-45)), math.cos(el) * math.sin(math.radians(-45)), math.sin(el)))
		cam("birch_game", tuple(Vector((0, 0, 4)) + d * 60), (0, 0, 4), ortho=26, res=(1400, 1000))

main()
