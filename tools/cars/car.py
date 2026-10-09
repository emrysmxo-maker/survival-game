# Реалистичные машины 2000–2026 (без логотипов): цельный гладкий кузов по сечениям (силуэт сбоку + план + завал
# боковин к крыше), остекление/фары/фонари/решётка/номера/арки — разметкой граней кузова, колёса с дисками,
# салон за стёклами. Краска и грязь — цвет вершин (Godot умножает сам). Метры, X — вдоль (нос в +X), Z — вверх.
#   /tmp/claude-0/blender/v/bin/python -I tools/cars/car.py <out_dir>   (ONLY=имена, SHOW=1 — рендер)
import bpy, bmesh, math, os, random, sys, zlib
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "houses"))
import house as H
from house import HB, mat, srgb2lin

H.FLAT.update({
	"paint": ((1.0, 1.0, 1.0), 0.30, 0.45), "paint_matte": ((1.0, 1.0, 1.0), 0.65, 0.05),
	"car_glass": ((0.05, 0.065, 0.075), 0.04, 0.7), "plastic": ((0.05, 0.05, 0.052), 0.7, 0.0),
	"tire": ((0.035, 0.035, 0.035), 0.95, 0.0), "rim": ((0.62, 0.63, 0.64), 0.3, 0.9), "chrome": ((0.85, 0.85, 0.85), 0.15, 1.0),
	"headlight": ((0.80, 0.82, 0.84), 0.05, 0.6), "taillight": ((0.60, 0.05, 0.04), 0.2, 0.1), "plate": ((0.93, 0.93, 0.9), 0.5, 0.0),
	"interior": ((0.07, 0.07, 0.075), 0.9, 0.0), "seam": ((0.025, 0.025, 0.025), 0.85, 0.0), "brake": ((0.30, 0.29, 0.28), 0.5, 0.7), "canvas": ((0.33, 0.36, 0.24), 0.95, 0.0), "frame": ((0.08, 0.08, 0.08), 0.6, 0.4),
})
SMOOTH = {"paint", "paint_matte", "car_glass", "tire"}

def lerp(a, b, t):
	return a + (b - a) * t

def interp(tab, x):
	"""Кусочно-гладкая интерполяция по точкам (x, y), x по возрастанию."""
	if x <= tab[0][0]:
		return tab[0][1]
	for (x0, y0), (x1, y1) in zip(tab, tab[1:]):
		if x <= x1:
			t = (x - x0) / max(x1 - x0, 1e-6)
			t = t * t * (3 - 2 * t) * 0.5 + t * 0.5
			return y0 + (y1 - y0) * t
	return tab[-1][1]

# ---------------- кузов ----------------
def body(hb, S, paint_col, rnd):
	"""Кузов по сечениям. S: L, W, top [(x/L, z)], clear, belt, tumble, sq (квадратность плана), glass зоны, светотехника."""
	L, W = S["L"], S["W"]
	clear, belt, tumble, sq = S["clear"], S["belt"], S.get("tumble", 0.16), S.get("sq", 6.0)
	ra = S["wheel_r"] + 0.07                                          # колёсные арки: низ кузова поднимается дугой над колесом
	NX = 72
	xs = sorted(set([L * (0.5 - 0.5 * math.cos(math.pi * i / NX)) for i in range(NX + 1)] +
		[ax + ra * math.sin(math.pi * (k / 10.0 - 0.5)) for ax in S["axles"] for k in range(11)] +    # гуще у торцов и над колёсами
		[x + d for x in S.get("seams", []) + S.get("tseams", []) for d in (-0.011, 0.011)] +            # щели дверей, капота, багажника
		[x + d for x in S.get("bpil", []) for d in (-0.05, 0.05)] +
		[x for od in ([S["open_door"]] if S.get("open_door") else []) for x in od[1:3]]))
	NX = len(xs) - 1
	def zt(x):
		return interp(S["top"], x / L)
	def zb(x):
		e = abs(2 * x / L - 1)
		z = clear + max(0.0, e - 0.82) / 0.18 * S.get("bumper_lift", 0.18)
		for ax in S["axles"]:
			dx = x - ax
			if abs(dx) < ra:
				z = max(z, S["wheel_r"] + math.sqrt(ra * ra - dx * dx) * 0.92)
		return z
	def hw(x):
		e = min(1.0, abs(2 * x / L - 1))
		return W / 2 * (1 - e ** sq) ** (1 / sq) if e < 1 else W / 2 * 0.25
	def section(x):
		w, t, b = max(hw(x), 0.05), zt(x), zb(x)
		zs = min(belt, t - 0.04)
		s = max(0.0, min(1.0, (t - belt) / 0.25))                       # есть ли «теплица» (стёкла) над поясом
		wr = lerp(w * 0.93, w * (1 - tumble), s)
		pts = [(0.0, b), (w * 0.86, b), (w * 0.985, b + min(0.1, (t - b) * 0.25))]
		for zl in (0.42, 0.55, 0.68, 0.80):
			z = min(max(zl, b + 0.12), zs - 0.01 * (5 - len(pts)))
			pts.append((w * (1.0 if z > b + 0.2 else 0.995), z))
		pts += [(w, zs), (w * 0.975, min(zs + 0.03, t - 0.015)), (wr, t - 0.05 * s - 0.01), (wr * 0.88, t), (0.0, t)]
		return pts
	rings = [section(x) for x in xs]
	nh = len(rings[0])
	# классификация граней: возвращает (материал, цвет)
	G = S["glass"]
	lights = S.get("lights", {})
	broken = S.get("broken", 0.0)
	seams, tseams, bpil = S.get("seams", []), S.get("tseams", []), S.get("bpil", [])
	od = S.get("open_door")
	sg = [g for g in G if g[2] == "side"]
	def classify(c, n):
		x, y, z = c.x, abs(c.y), c.z
		t = zt(x)
		# открытая дверь: проём (видно салон)
		if od and c.y * od[0] > 0 and od[1] < x < od[2] and abs(n.y) > 0.3 and zb(x) + 0.03 < z < t - 0.03:
			return "hole", None
		# центральная стойка — чёрная
		if z > belt + 0.03 and z < t - 0.025 and abs(n.y) > 0.35 and any(abs(x - xb) < 0.05 for xb in bpil):
			return "plastic", None
		# молдинг по низу окон
		if sg and abs(n.y) > 0.2 and belt - 0.004 < z < belt + 0.032 and sg[0][0] < x < sg[0][1]:
			return "plastic", None
		# щели дверей (бока) и капота/багажника (верх)
		if abs(n.y) > 0.35 and zb(x) + 0.04 < z < belt + 0.01 and any(abs(x - xs_) < 0.011 for xs_ in seams):
			return "seam", None
		if n.z > 0.5 and y < hw(x) * 0.93 and any(abs(x - xs_) < 0.011 for xs_ in tseams):
			return "seam", None
		# стёкла
		if z > belt + 0.03 and z < t - 0.025:
			if n.z < 0.92:
				for (x0, x1, kind) in G:
					if x0 < x < x1:
						if kind == "side" and abs(n.y) > 0.35:
							return ("hole" if rnd.random() < broken else "car_glass"), None
						if kind == "front" and n.x > 0.2 and y < hw(x) * 0.86:
							return ("hole" if rnd.random() < broken * 0.6 else "car_glass"), None
						if kind == "rear" and n.x < -0.2 and y < hw(x) * 0.86:
							return ("hole" if rnd.random() < broken else "car_glass"), None
		# подкрылки (низ над колесом)
		for ax in S["axles"]:
			if abs(x - ax) < ra and n.z < -0.3:
				return "plastic", None
		# светотехника и решётка спереди/сзади
		if n.x > 0.45:
			hl = lights.get("head", (0.70, 0.84, 0.30, 0.62))                 # z0, z1, |y| от, до
			if hl[0] < z < hl[1] and hl[2] < y < hl[3]:
				return "headlight", None
			gr = lights.get("grille", (0.50, 0.72, 0.0, 0.28))
			if gr[0] < z < gr[1] and y < gr[3]:
				return "plastic", None
			if 0.36 < z < 0.48 and y < 0.26:
				return "plate", None
			if S.get("plastic_bumper") and z < 0.48:
				return "plastic", None
		if n.x < -0.45:
			tl = lights.get("tail", (0.78, 0.95, 0.40, 0.70))
			if tl[0] < z < tl[1] and tl[2] < y < tl[3]:
				return "taillight", None
			if lights.get("rplate", (0.55, 0.68))[0] < z < lights.get("rplate", (0.55, 0.68))[1] and y < 0.27:
				return "plate", None
			if S.get("plastic_bumper") and z < 0.5:
				return "plastic", None
		if S.get("plastic_bumper") and z < clear + 0.14:
			return "plastic", None                                          # пороги/низ
		# полосы служебных машин
		for (z0, z1, col) in S.get("stripes", []):
			if z0 < z < z1 and abs(n.y) > 0.5:
				return "paint", col
		return "paint", None
	# грани
	bms = {}
	vcache = {}
	def vert(m, i, j, side):
		y, z = rings[i][j]
		if y == 0.0:
			side = 1                                                    # точки на оси — общие для обеих сторон (без шва)
		key = (m, i, j, side)
		if key not in vcache:
			bm = hb._bm(mat(m))
			vcache[key] = bm.verts.new((xs[i], side * y, z))
		return vcache[key]
	cl_paint = tuple(srgb2lin(paint_col))
	for i in range(NX):
		for j in range(nh - 1):
			for side in (1, -1):
				p = [Vector((xs[i], side * rings[i][j][0], rings[i][j][1])), Vector((xs[i + 1], side * rings[i + 1][j][0], rings[i + 1][j][1])),
					Vector((xs[i + 1], side * rings[i + 1][j + 1][0], rings[i + 1][j + 1][1])), Vector((xs[i], side * rings[i][j + 1][0], rings[i][j + 1][1]))]
				c = (p[0] + p[1] + p[2] + p[3]) / 4
				n = (p[2] - p[0]).cross(p[3] - p[1])
				if n.length < 1e-9:
					continue
				n.normalize()
				mid = Vector((c.x, 0.0, (zb(c.x) + zt(c.x)) * 0.5))
				outward = n.dot(c - mid) >= 0.0
				if not outward:
					n = -n                                             # наружная нормаль
				m, col = classify(c, n)
				if m == "hole":
					continue
				vs = [vert(m, i, j, side), vert(m, i + 1, j, side), vert(m, i + 1, j + 1, side), vert(m, i, j + 1, side)]
				if not outward:
					vs = vs[::-1]
				try:
					f = hb._bm(mat(m)).faces.new(vs)
				except ValueError:
					continue
				cc = col if col is not None else (paint_col if m in ("paint", "paint_matte") else (1, 1, 1))
				hb._paint(hb._bm(mat(m)), [f], cc)
	# торцы
	for i, sgn in ((0, -1), (NX, 1)):
		pts = [(xs[i], y, z) for (y, z) in rings[i]] + [(xs[i], -y, z) for (y, z) in rings[i][-2:0:-1]]
		bm = hb._bm(mat("paint"))
		try:
			vs = [bm.verts.new(p) for p in (pts if sgn > 0 else pts[::-1])]
			f = bm.faces.new(vs)
			hb._paint(bm, [f], paint_col)
		except ValueError:
			pass
	return zt, hw

def wheel(hb, x, y, z, r, w=0.21, flat=False, rim="rim", rim_k=0.66, burnt=False, spokes=5):
	"""Колесо: шина с закруглённой боковиной и протектором, литой диск со спицами (между спицами — тормозной диск и тьма)."""
	if flat:
		z -= r * 0.13
	s = 1 if y > 0 else -1
	if not burnt:
		hb.cyl(mat("tire"), (x, y, z), r, w * 0.82, "Y", 28)
		hb.cyl(mat("tire"), (x, y, z), r * 0.965, w, "Y", 28)                # боковина шире протектора
		for k in range(14):                                                  # грунтозацепы протектора
			a = k * 2 * math.pi / 14
			hb.box(mat("tire"), (x + math.cos(a) * r, y, z + math.sin(a) * r), (0.05, w * 0.7, 0.03), (0.8, 0.8, 0.8), rot=(0, math.pi / 2 - a, 0))
	rr = r * rim_k
	yo = y + s * (w / 2 - 0.02)
	cr = (0.45, 0.4, 0.35) if burnt else (1, 1, 1)
	hb.cyl(mat("frame"), (x, yo - s * 0.03, z), rr * 0.97, 0.02, "Y", 20)       # тьма за спицами
	hb.cyl(mat("brake"), (x, yo - s * 0.05, z), rr * 0.72, 0.03, "Y", 16, col=cr)
	# обод: кольцо из сегментов
	for k in range(16):
		a0, a1 = k * 2 * math.pi / 16, (k + 1) * 2 * math.pi / 16
		hb.beam(mat(rim), (x + math.cos(a0) * rr, yo, z + math.sin(a0) * rr), (x + math.cos(a1) * rr, yo, z + math.sin(a1) * rr), 0.045, 0.06, col=cr)
	for k in range(spokes):                                              # спицы
		a = k * 2 * math.pi / spokes + 0.3
		p1 = (x + math.cos(a) * rr * 0.95, yo + s * 0.005, z + math.sin(a) * rr * 0.95)
		hb.beam(mat(rim), (x + math.cos(a) * rr * 0.22, yo + s * 0.02, z + math.sin(a) * rr * 0.22), p1, 0.055, 0.03, col=cr)
	hb.cyl(mat(rim), (x, yo + s * 0.02, z), rr * 0.26, 0.04, "Y", 12, col=cr)  # ступица
	hb.cyl(mat("plastic"), (x, yo + s * 0.04, z), rr * 0.12, 0.01, "Y", 8)
	for k in range(5):                                                   # гайки
		a = k * 2 * math.pi / 5
		hb.cyl(mat("chrome"), (x + math.cos(a) * rr * 0.17, yo + s * 0.042, z + math.sin(a) * rr * 0.17), 0.012, 0.012, "Y", 6)

def finish(hb, name):
	ob = hb.build(name)
	for p in ob.data.polygons:
		p.use_smooth = ob.data.materials[p.material_index].name in SMOOTH
	return ob

# ---------------- легковые ----------------
CARS = {
	# седан (Веста/Солярис-класс)
	"sedan": dict(L=4.42, W=1.78, top=[(0, 0.64), (0.025, 0.96), (0.2, 1.0), (0.31, 1.40), (0.36, 1.47), (0.6, 1.48), (0.73, 1.0), (0.96, 0.82), (1.0, 0.6)],
		clear=0.17, belt=0.98, tumble=0.17, sq=6.0, wheel_r=0.31, axles=(0.86, 3.45), glass=[(1.05, 1.6, "rear"), (1.4, 3.15, "side"), (2.62, 3.25, "front")],
		lights={"head": (0.66, 0.80, 0.38, 0.80), "tail": (0.80, 0.95, 0.45, 0.82), "grille": (0.48, 0.66, 0.0, 0.32), "rplate": (0.62, 0.76)}, plastic_bumper=False),
	# хэтчбек
	"hatch": dict(L=4.00, W=1.72, top=[(0, 0.66), (0.02, 1.02), (0.08, 1.30), (0.16, 1.44), (0.55, 1.46), (0.70, 1.0), (0.96, 0.80), (1.0, 0.6)],
		clear=0.16, belt=0.97, tumble=0.17, sq=5.0, wheel_r=0.30, axles=(0.68, 3.22), glass=[(0.15, 0.62, "rear"), (0.5, 2.75, "side"), (2.2, 2.85, "front")],
		lights={"head": (0.68, 0.82, 0.38, 0.78), "tail": (0.82, 1.0, 0.45, 0.80), "grille": (0.48, 0.66, 0.0, 0.32), "rplate": (0.55, 0.68)}),
	# кроссовер (Дастер/Крета-класс)
	"crossover": dict(L=4.34, W=1.82, top=[(0, 0.72), (0.02, 1.2), (0.06, 1.62), (0.12, 1.69), (0.6, 1.70), (0.73, 1.15), (0.96, 0.98), (1.0, 0.7)],
		clear=0.21, belt=1.12, tumble=0.12, sq=5.0, wheel_r=0.35, axles=(0.82, 3.49), glass=[(0.15, 0.55, "rear"), (0.45, 3.0, "side"), (2.55, 3.15, "front")],
		lights={"head": (0.82, 0.96, 0.40, 0.82), "tail": (0.92, 1.12, 0.48, 0.84), "grille": (0.56, 0.80, 0.0, 0.40), "rplate": (0.62, 0.78)}, plastic_bumper=True, bumper_lift=0.22),
	# внедорожник (Нива Тревел-класс)
	"suv": dict(L=4.10, W=1.80, top=[(0, 0.75), (0.015, 1.25), (0.04, 1.62), (0.1, 1.66), (0.62, 1.66), (0.73, 1.12), (0.96, 1.0), (1.0, 0.72)],
		clear=0.22, belt=1.10, tumble=0.10, sq=7.0, wheel_r=0.36, axles=(0.8, 3.25), glass=[(0.12, 0.5, "rear"), (0.4, 2.85, "side"), (2.45, 3.0, "front")],
		lights={"head": (0.80, 0.95, 0.40, 0.80), "tail": (0.90, 1.12, 0.52, 0.86), "grille": (0.56, 0.82, 0.0, 0.42), "rplate": (0.62, 0.78)}, plastic_bumper=True, bumper_lift=0.2),
	# классика (ВАЗ-2107-класс): угловатый
	"classic": dict(L=4.13, W=1.62, top=[(0, 0.66), (0.015, 0.94), (0.2, 0.98), (0.29, 1.36), (0.33, 1.42), (0.63, 1.43), (0.74, 0.98), (0.985, 0.88), (1.0, 0.62)],
		clear=0.17, belt=0.96, tumble=0.12, sq=14.0, wheel_r=0.29, axles=(0.85, 3.27), glass=[(0.95, 1.4, "rear"), (1.3, 3.0, "side"), (2.62, 3.08, "front")],
		lights={"head": (0.66, 0.80, 0.34, 0.76), "tail": (0.70, 0.90, 0.35, 0.78), "grille": (0.62, 0.80, 0.0, 0.33), "rplate": (0.52, 0.66)}),
	# «Нива» 4×4 (2121-класс)
	"niva": dict(L=3.74, W=1.68, top=[(0, 0.72), (0.012, 1.14), (0.035, 1.58), (0.08, 1.63), (0.62, 1.64), (0.72, 1.05), (0.975, 0.98), (1.0, 0.7)],
		clear=0.22, belt=1.06, tumble=0.1, sq=12.0, wheel_r=0.34, axles=(0.62, 2.82), glass=[(0.06, 0.32, "rear"), (0.3, 2.62, "side"), (2.28, 2.72, "front")],
		lights={"head": (0.78, 0.92, 0.42, 0.74), "tail": (0.82, 1.02, 0.52, 0.80), "grille": (0.6, 0.86, 0.0, 0.4), "rplate": (0.62, 0.76)}),
	# универсал/компактвэн (Ларгус-класс)
	"wagon": dict(L=4.47, W=1.75, top=[(0, 0.66), (0.01, 1.2), (0.03, 1.60), (0.08, 1.66), (0.62, 1.67), (0.74, 1.04), (0.965, 0.88), (1.0, 0.62)],
		clear=0.17, belt=1.02, tumble=0.12, sq=7.0, wheel_r=0.31, axles=(0.85, 3.75), glass=[(0.05, 0.4, "rear"), (0.35, 3.25, "side"), (2.8, 3.35, "front")],
		lights={"head": (0.70, 0.84, 0.38, 0.78), "tail": (0.85, 1.25, 0.62, 0.84), "grille": (0.5, 0.7, 0.0, 0.34), "rplate": (0.55, 0.7)}),
	# фургон (Газель Next-класс), окна только в кабине
	"van": dict(L=5.63, W=2.07, top=[(0, 0.62), (0.005, 2.2), (0.02, 2.28), (0.76, 2.3), (0.79, 2.18), (0.87, 1.30), (0.975, 1.10), (1.0, 0.65)],
		clear=0.21, belt=1.30, tumble=0.04, sq=16.0, wheel_r=0.36, axles=(1.25, 4.39), glass=[(4.25, 4.85, "side"), (4.6, 4.95, "front")],
		lights={"head": (0.95, 1.12, 0.48, 0.92), "tail": (0.85, 1.25, 0.86, 1.02), "grille": (0.68, 0.98, 0.0, 0.45), "rplate": (0.5, 0.64)}, plastic_bumper=True, bumper_lift=0.15),
	# «буханка» (УАЗ-452-класс): скруглённая коробка, окна по бокам
	"buhanka": dict(L=4.36, W=1.94, top=[(0, 0.6), (0.01, 1.7), (0.04, 2.0), (0.1, 2.08), (0.86, 2.08), (0.94, 1.9), (0.985, 1.25), (1.0, 0.62)],
		clear=0.24, belt=1.30, tumble=0.10, sq=7.0, wheel_r=0.37, axles=(0.85, 3.15), glass=[(0.0, 0.25, "rear"), (0.3, 3.95, "side"), (3.95, 4.36, "front")],
		lights={"head": (0.80, 0.95, 0.58, 0.86), "tail": (0.75, 0.95, 0.80, 0.94), "grille": (0.62, 0.95, 0.0, 0.42), "rplate": (0.52, 0.66)}),
	# автобус (ПАЗ-класс)
	"bus": dict(L=7.6, W=2.48, top=[(0, 0.75), (0.005, 2.55), (0.02, 2.88), (0.05, 2.95), (0.94, 2.95), (0.98, 2.75), (0.995, 1.45), (1.0, 0.75)],
		clear=0.30, belt=1.40, tumble=0.04, sq=18.0, wheel_r=0.47, axles=(1.65, 5.25), glass=[(0.0, 0.08, "rear"), (0.3, 7.25, "side"), (7.15, 7.6, "front")],
		lights={"head": (0.85, 1.05, 0.75, 1.15), "tail": (1.0, 1.3, 0.95, 1.18), "grille": (0.7, 1.2, 0.0, 0.6), "rplate": (0.55, 0.7)}),
}

DOORS = {"sedan": 4, "hatch": 4, "crossover": 4, "suv": 4, "classic": 4, "niva": 2, "wagon": 4, "van": 1, "buhanka": 1, "bus": 0}
def car(name, kind, paint, seed, broken=0.0, flat=0, dirt=0.35, stripes=None, rust=0.0, burnt=False, beacon=None, roofrack=False, door_open=False, luggage=False):
	rnd = random.Random(seed)
	S = dict(CARS[kind])
	S["broken"] = 1.0 if burnt else broken
	# двери: щели, центральная стойка, ручки; капот и багажник — щели сверху
	r0, axl = S["wheel_r"], S["axles"]
	fg = [g for g in S["glass"] if g[2] == "front"]
	rg = [g for g in S["glass"] if g[2] == "rear"]
	nd = DOORS[kind]
	xf = axl[1] - r0 - 0.12                                                # передний край передней двери (нос в +X)
	doors = []
	if nd == 4:
		xr = axl[0] + r0 + 0.12
		xb = (xf + xr) / 2 + 0.06
		doors = [(xb, xf), (xr, xb)]
		S["bpil"] = [xb]
	elif nd == 2:
		doors = [(xf - 1.2, xf)]
		S["bpil"] = [xf - 1.2]
	elif nd == 1 and fg:
		doors = [(fg[0][0] - 0.95, fg[0][0] - 0.05)]
	S["seams"] = sorted(set([d[0] for d in doors] + [d[1] for d in doors]))
	ts = []
	if fg and kind not in ("van", "bus", "buhanka"):
		ts.append(fg[0][1] + 0.05)                                        # задний край капота — у основания лобового
	if rg and kind in ("sedan", "classic"):
		ts.append(rg[0][0] - 0.06)                                        # крышка багажника
	S["tseams"] = ts
	if door_open and doors:
		S["open_door"] = (1 if rnd.random() < 0.5 else -1, doors[0][0] + 0.02, doors[0][1] - 0.02)
	if stripes:
		S["stripes"] = stripes
	hb = HB(keep_winding=True)
	col = (0.07, 0.06, 0.055) if burnt else paint
	zt, hw = body(hb, S, col, rnd)
	L, W, r = S["L"], S["W"], S["wheel_r"]
	# салон (виден через стёкла и разбитые окна)
	gl = [g for g in S["glass"] if g[2] == "side"]
	if gl:
		x0, x1 = gl[0][0], gl[0][1]
		hb.box(mat("interior"), ((x0 + x1) / 2, 0, (S["belt"] + S["clear"]) / 2 + 0.15), (x1 - x0, W * 0.8, S["belt"] - S["clear"]), (1, 1, 1))
		for k in range(2 if kind not in ("van", "bus") else 1):            # спинки кресел
			xx = x1 - 0.55 - k * 0.95
			for sy in (-0.38, 0.38):
				hb.box(mat("interior"), (xx, sy, S["belt"] + 0.12), (0.12, 0.5, 0.55), (1.2, 1.2, 1.2))
	# колёса
	tw = W / 2 - 0.12
	for ax in S["axles"]:
		for sy in (-1, 1):
			fl = flat > 0 and rnd.random() < 0.5
			wheel(hb, ax, sy * tw, r, r, 0.22 if kind != "bus" else 0.3, fl, burnt=burnt)
	if kind == "bus":                                                     # сдвоенные задние
		for sy in (-1, 1):
			wheel(hb, S["axles"][0], sy * (tw - 0.3), r, r, 0.28, burnt=burnt)
	# ручки дверей
	for (d0, d1) in doors:
		xh = d0 + 0.22
		for sy in (-1, 1):
			if S.get("open_door") and sy == S["open_door"][0] and (d0, d1) == doors[0]:
				continue
			hb.box(mat("chrome" if kind in ("sedan", "classic") else "plastic"), (xh, sy * (W / 2 + 0.008), S["belt"] - 0.09), (0.19, 0.03, 0.035), (1, 1, 1))
	# открытая дверь: створка повёрнута наружу на петлях у переднего края
	if S.get("open_door"):
		sgn, d0, d1 = S["open_door"]
		dl = d1 - d0
		a = math.radians(rnd.uniform(40, 65))
		hx, hy = d1, sgn * (W / 2 - 0.02)
		dx, dy = -math.cos(a), sgn * math.sin(a)
		zb0 = S["clear"] + 0.12
		zt0 = S["belt"]
		cx, cy = hx + dx * dl / 2, hy + dy * dl / 2
		hb.box(mat("paint"), (cx, cy, (zb0 + zt0) / 2), (dl, 0.07, zt0 - zb0), col, rot=(0, 0, -sgn * a))
		hb.box(mat("interior"), (cx - sgn * 0.0, cy - sgn * 0.035 * math.cos(a), (zb0 + zt0) / 2), (dl * 0.92, 0.02, (zt0 - zb0) * 0.85), (1, 1, 1), rot=(0, 0, -sgn * a))
		gz = zt(d1 - 0.3) - 0.04
		if gz > zt0 + 0.15:                                               # рамка окна двери
			hb.box(mat("car_glass"), (cx, cy, (zt0 + gz) / 2), (dl * 0.85, 0.02, gz - zt0), (1, 1, 1), rot=(0, 0, -sgn * a))
	# зеркала: ножка + корпус
	if fg:
		xm_ = fg[0][0] + 0.02 if kind not in ("bus",) else L - 0.2
		zm = S["belt"] + 0.1
		for sy in (-1, 1):
			yy = sy * (hw(xm_) + 0.02)
			hb.box(mat("plastic"), (xm_, yy + sy * 0.06, zm - 0.02), (0.07, 0.12, 0.03), (1, 1, 1))
			hb.box(mat("plastic" if kind in ("crossover", "suv", "van", "niva", "buhanka") else "paint"), (xm_ - 0.03, yy + sy * 0.17, zm + 0.02), (0.1, 0.17, 0.12), col)
			hb.box(mat("car_glass"), (xm_ - 0.085, yy + sy * 0.17, zm + 0.02), (0.01, 0.14, 0.09), (1, 1, 1))
		# дворники у основания лобового стекла
		xw = fg[0][1] - 0.04
		zw = zt(xw) + 0.02
		for sy in (-0.45, 0.15):
			hb.beam(mat("plastic"), (xw, sy * W / 2 + 0.25, zw), (xw - 0.12, sy * W / 2 - 0.25, zw + 0.08), 0.02, 0.015)
	# низ: решётка-воздухозаборник, противотуманки, выхлоп, антенна, днище
	if kind not in ("bus",):
		hb.box(mat("plastic"), (L - 0.02, 0, S["clear"] + 0.16), (0.05, W * 0.5, 0.1), (0.6, 0.6, 0.6))
		for sy in (-1, 1):
			hb.cyl(mat("headlight"), (L - 0.02, sy * W * 0.34, S["clear"] + 0.17), 0.045, 0.03, "X", 10)
	hb.cyl(mat("chrome"), (0.04, -W * 0.3, S["clear"] + 0.06), 0.03, 0.1, "X", 8, col=(0.5, 0.45, 0.4))
	hb.box(mat("frame"), (L / 2, 0, S["clear"] + 0.04), (L * 0.8, W * 0.8, 0.04))
	if kind in ("sedan", "hatch", "crossover", "classic", "niva"):
		xa_ = L * 0.3
		hb.beam(mat("plastic"), (xa_, 0, zt(xa_)), (xa_ - 0.15, 0, zt(xa_) + 0.18), 0.025, 0.012)
	# колёсные ниши — тёмные
	for axx in axl:
		for sy in (-1, 1):
			hb.cyl(mat("frame"), (axx, sy * (W / 2 - 0.36), r0), r0 + 0.07, 0.3, "Y", 16)
	# багажник на крыше / маячки
	if roofrack or luggage:
		for sy in (-1, 1):
			hb.box(mat("plastic"), (L * 0.42, sy * (W / 2 - 0.25), zt(L * 0.42) + 0.04), (L * 0.42, 0.04, 0.05), (1, 1, 1))
	if luggage:                                                           # вещи на крыше: уезжали в спешке
		zr = zt(L * 0.42) + 0.07
		for k in range(rnd.randint(2, 4)):
			bx = L * 0.42 + rnd.uniform(-0.5, 0.5)
			by = rnd.uniform(-0.35, 0.35)
			sz = (rnd.uniform(0.4, 0.7), rnd.uniform(0.3, 0.5), rnd.uniform(0.18, 0.3))
			bc = rnd.choice([(0.25, 0.42, 0.75), (0.72, 0.2, 0.15), (0.75, 0.68, 0.5), (0.3, 0.55, 0.3), (0.85, 0.55, 0.15)])
			hb.box(mat("canvas"), (bx, by, zr + sz[2] / 2), sz, bc, rot=(0, 0, rnd.uniform(-0.4, 0.4)))
	if beacon:
		xb = L * 0.6 if kind != "van" else L * 0.75
		hb.box(mat("plastic"), (xb, 0, zt(xb) + 0.05), (0.25, 1.0, 0.06), (1, 1, 1))
		for sy, bc in ((-1, beacon[0]), (1, beacon[1])):
			hb.box(mat("taillight"), (xb, sy * 0.28, zt(xb) + 0.12), (0.22, 0.42, 0.1), bc)
	ob = finish(hb, name)
	# грязь/ржавчина/копоть — цвет вершин: низ темнее и рыжее
	cl = ob.data.color_attributes["Color"]
	me = ob.data
	for poly in me.polygons:
		mname = me.materials[poly.material_index].name
		for li in poly.loop_indices:
			v = me.vertices[me.loops[li].vertex_index].co
			c = Vector(cl.data[li].color[:3])
			k = max(0.0, min(1.0, (0.75 - v.z) / 0.6)) * dirt
			dirt_c = Vector(srgb2lin((0.36, 0.30, 0.22)))
			c = c.lerp(dirt_c, k * (0.8 if mname in ("paint", "paint_matte", "plastic") else 0.4))
			if rust > 0 and mname == "paint":
				nz = math.sin(v.x * 7.1 + v.z * 9.3) * math.sin(v.x * 3.3 - v.y * 5.7 + v.z * 4.1)
				if nz > 1.0 - rust and v.z < 0.9:
					c = c.lerp(Vector(srgb2lin((0.34, 0.16, 0.07))), 0.85)
			cl.data[li].color = (c.x, c.y, c.z, 1.0)
	return ob

# ---------------- грузовики, трактор ----------------
def truck(name, paint, seed, cargo="flat", dirt=0.45):
	"""КамАЗ-класс: кабина над мотором, рама, 3 оси; кузов: flat (бортовой), tent (тент), logs (лесовоз), tank (пожарный)."""
	rnd = random.Random(seed)
	hb = HB()
	cab = dict(L=2.35, W=2.5, top=[(0, 1.2), (0.01, 3.05), (0.05, 3.1), (0.82, 3.1), (0.9, 2.95), (0.98, 1.95), (1.0, 1.15)],
		clear=1.05, belt=2.05, tumble=0.04, sq=20.0, wheel_r=0.0, axles=(), glass=[(0.3, 1.9, "side"), (1.9, 2.35, "front")],
		lights={"head": (1.18, 1.32, 0.75, 1.15), "grille": (1.4, 1.95, 0.0, 0.9), "tail": (0, 0, 0, 0)}, broken=0.15)
	# кабина сдвигается вперёд: строим в своих координатах и переносим
	sub = HB()
	body(sub, cab, paint, rnd)
	hb.bms.update({})
	cabo = finish(sub, name + "_cab")
	cabo.location.x = 5.4
	# рама, бак, бамперы
	hb.box(mat("frame"), (3.4, 0, 0.95), (7.4, 0.9, 0.25))
	hb.box(mat("plastic"), (7.8, 0, 0.75), (0.25, 2.45, 0.35), (1, 1, 1))
	hb.cyl(mat("metal_paint"), (4.4, -1.05, 0.95), 0.32, 1.0, "X", 12, col=(0.7, 0.7, 0.7))
	for ax in (1.3, 2.65, 6.4):
		for sy in (-1, 1):
			wheel(hb, ax, sy * 1.0, 0.54, 0.54, 0.34, rim_k=0.55)
	if cargo == "flat":
		hb.box(mat("planks_brown"), (2.4, 0, 1.25), (5.6, 2.45, 0.1), (0.8, 0.8, 0.8))
		for sy in (-1, 1):
			hb.box(mat("metal_paint"), (2.4, sy * 1.2, 1.65), (5.6, 0.05, 0.7), paint)
		hb.box(mat("metal_paint"), (-0.38, 0, 1.65), (0.05, 2.45, 0.7), paint)
		hb.box(mat("metal_paint"), (5.15, 0, 1.75), (0.06, 2.45, 0.9), paint)
	elif cargo == "tent":
		hb.box(mat("planks_brown"), (2.4, 0, 1.25), (5.6, 2.45, 0.1), (0.8, 0.8, 0.8))
		for sy in (-1, 1):
			hb.box(mat("metal_paint"), (2.4, sy * 1.2, 1.55), (5.6, 0.05, 0.5), paint)
		arc = [(-1.2, 1.35)] + [(-1.2 * math.cos(a), 2.95 + 0.35 * math.sin(a)) for a in [math.pi * k / 10 for k in range(11)]] + [(1.2, 1.35)]
		hb.poly(mat("canvas"), [(-0.35, y, z) for (y, z) in arc], (5.5, 0, 0), (1, 1, 1))   # тент: борта + выгнутый верх
	elif cargo == "logs":
		for sy in (-1, 1):
			for xx in (0.5, 2.4, 4.3):
				hb.box(mat("frame"), (xx, sy * 1.15, 1.9), (0.12, 0.12, 1.5))
		for i in range(9):
			yy = -0.85 + (i % 4) * 0.55
			zz = 1.55 + (i // 4) * 0.48
			hb.cyl(mat("planks_brown"), (2.6 + rnd.uniform(-0.3, 0.3), yy, zz), 0.24, 6.2, "X", 10, col=(0.7, 0.6, 0.5))
	elif cargo == "tank":
		hb.cyl(mat("paint"), (2.4, 0, 2.05), 1.1, 5.4, "X", 18, col=paint)
		hb.box(mat("metal_paint"), (2.4, 0, 3.2), (5.0, 0.6, 0.06), (0.8, 0.8, 0.8))
	ob = finish(hb, name)
	# склеить с кабиной
	bpy.ops.object.select_all(action="DESELECT")
	cabo.select_set(True); ob.select_set(True)
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.join()
	ob = bpy.context.view_layer.objects.active
	ob.name = name
	for p in ob.data.polygons:
		p.use_smooth = ob.data.materials[p.material_index].name in SMOOTH
	return ob

def tractor(name, paint, seed):
	"""Трактор МТЗ-82-класс: капот, кабина-«клетка» со стёклами, большие задние колёса."""
	hb = HB()
	hb.box(mat("paint"), (2.35, 0, 1.25), (1.6, 0.85, 0.85), paint)                  # капот
	hb.box(mat("plastic"), (3.18, 0, 1.25), (0.06, 0.8, 0.75), (1, 1, 1))            # решётка
	hb.box(mat("frame"), (1.6, 0, 0.8), (2.6, 0.7, 0.4))
	hb.box(mat("paint"), (0.7, 0, 1.35), (1.3, 1.5, 0.12), paint)                    # пол кабины
	for (x, y) in ((0.1, -0.72), (0.1, 0.72), (1.3, -0.72), (1.3, 0.72)):
		hb.box(mat("paint"), (x, y, 2.05), (0.07, 0.07, 1.4), paint)
	hb.box(mat("paint"), (0.7, 0, 2.78), (1.45, 1.6, 0.1), paint)                    # крыша
	for sy in (-1, 1):
		hb.box(mat("car_glass"), (0.7, sy * 0.73, 2.05), (1.12, 0.02, 1.2))
	hb.box(mat("car_glass"), (1.32, 0, 2.05), (0.02, 1.38, 1.15))
	hb.box(mat("car_glass"), (0.08, 0, 2.15), (0.02, 1.38, 0.9))
	hb.cyl(mat("frame"), (2.7, 0.3, 2.2), 0.06, 1.3, "Z", 8)                        # выхлоп
	for sy in (-1, 1):
		wheel(hb, 0.55, sy * 0.95, 0.78, 0.78, 0.4, rim_k=0.55)
		wheel(hb, 2.9, sy * 0.8, 0.48, 0.48, 0.26, rim_k=0.55)
		hb.box(mat("paint"), (0.55, sy * 0.95, 1.6), (1.5, 0.48, 0.05), paint)       # крылья
	hb.box(mat("headlight"), (3.22, -0.3, 1.45), (0.04, 0.15, 0.1)); hb.box(mat("headlight"), (3.22, 0.3, 1.45), (0.04, 0.15, 0.1))
	ob = finish(hb, name)
	return ob

# ---------------- набор моделей ----------------
P = {   # цвета (sRGB): приглушённые реальные
	"white": (0.86, 0.86, 0.84), "silver": (0.62, 0.63, 0.64), "graphite": (0.33, 0.34, 0.36), "black": (0.07, 0.07, 0.08),
	"navy": (0.18, 0.26, 0.42), "darkred": (0.52, 0.11, 0.10), "beige": (0.66, 0.60, 0.48), "brown": (0.50, 0.37, 0.25),
	"darkgreen": (0.24, 0.35, 0.24), "olive": (0.40, 0.42, 0.26), "taxi": (0.86, 0.66, 0.12), "orange": (0.80, 0.38, 0.10),
	"blue": (0.20, 0.35, 0.60), "red": (0.62, 0.10, 0.08), "busyellow": (0.88, 0.70, 0.18), "mtzblue": (0.18, 0.32, 0.55),
}
def J(*a, **k):
	return lambda: car(*a, **k)
JOBS = {
	# старые имена (используются в расстановке) — новые реалистичные машины
	"car_sedan_red": J("car_sedan_red", "sedan", P["darkred"], 11, broken=0.2, flat=1),
	"car_sedan_blue": J("car_sedan_blue", "hatch", P["navy"], 12, broken=0.1),
	"car_sedan_white": J("car_sedan_white", "sedan", P["white"], 13, broken=0.3, flat=1, door_open=True),
	"car_sedan_burnt": J("car_sedan_burnt", "classic", P["black"], 14, burnt=True, dirt=0.8),
	"car_sedan_green": J("car_sedan_green", "classic", P["darkgreen"], 15, broken=0.4, flat=1, rust=0.25, luggage=True),
	"car_sedan_yellow": J("car_sedan_yellow", "sedan", P["taxi"], 16, broken=0.15),
	"car_van_olive": J("car_van_olive", "buhanka", P["olive"], 17, broken=0.3, rust=0.2, dirt=0.5),
	"car_van_white": J("car_van_white", "van", P["white"], 18, broken=0.1),
	"car_van_orange": J("car_van_orange", "van", P["orange"], 19, broken=0.2, dirt=0.5),
	"car_bus_yellow": J("car_bus_yellow", "bus", P["busyellow"], 20, broken=0.35, flat=1, stripes=[(0.9, 1.05, (0.85, 0.85, 0.82))]),
	"car_bus_blue": J("car_bus_blue", "bus", P["white"], 21, broken=0.25, stripes=[(1.0, 1.25, (0.2, 0.35, 0.6))]),
	# новые
	"car_solaris_silver": J("car_solaris_silver", "sedan", P["silver"], 31, broken=0.1),
	"car_granta_graphite": J("car_granta_graphite", "sedan", P["graphite"], 32, broken=0.2, flat=1, door_open=True),
	"car_vesta_black": J("car_vesta_black", "sedan", P["black"], 33, broken=0.05),
	"car_hatch_white": J("car_hatch_white", "hatch", P["white"], 34, broken=0.2, door_open=True),
	"car_hatch_red": J("car_hatch_red", "hatch", P["red"], 35, broken=0.1, flat=1),
	"car_duster_brown": J("car_duster_brown", "crossover", P["brown"], 36, broken=0.1, roofrack=True),
	"car_crossover_silver": J("car_crossover_silver", "crossover", P["silver"], 37, broken=0.05),
	"car_crossover_white": J("car_crossover_white", "crossover", P["white"], 38, broken=0.15, flat=1, luggage=True, door_open=True),
	"car_suv_green": J("car_suv_green", "suv", P["darkgreen"], 39, broken=0.1, roofrack=True),
	"car_niva_beige": J("car_niva_beige", "niva", P["beige"], 40, broken=0.3, rust=0.3, door_open=True),
	"car_niva_white": J("car_niva_white", "niva", P["white"], 41, broken=0.2, rust=0.15),
	"car_classic_blue": J("car_classic_blue", "classic", P["blue"], 42, broken=0.5, flat=1, rust=0.35, luggage=True),
	"car_wagon_silver": J("car_wagon_silver", "wagon", P["silver"], 43, broken=0.1),
	"car_wagon_beige": J("car_wagon_beige", "wagon", P["beige"], 44, broken=0.25, flat=1, luggage=True, door_open=True),
	"car_police": J("car_police", "sedan", P["white"], 45, broken=0.2, stripes=[(0.55, 0.78, (0.12, 0.28, 0.62))], beacon=((0.6, 0.05, 0.04), (0.1, 0.2, 0.75)), door_open=True),
	"car_ambulance": J("car_ambulance", "van", P["white"], 46, broken=0.15, stripes=[(0.95, 1.12, (0.75, 0.08, 0.06))], beacon=((0.1, 0.2, 0.75), (0.1, 0.2, 0.75))),
	# брошенные: сгоревшие и разбитые (стёкла выбиты, колёса спущены, ржавчина)
	"car_crossover_burnt": J("car_crossover_burnt", "crossover", P["black"], 71, burnt=True, dirt=0.8),
	"car_hatch_burnt": J("car_hatch_burnt", "hatch", P["black"], 72, burnt=True, dirt=0.8),
	"car_solaris_wreck": J("car_solaris_wreck", "sedan", P["silver"], 73, broken=0.9, flat=2, rust=0.3, dirt=0.7, door_open=True),
	"car_truck_blue": lambda: truck("car_truck_blue", P["blue"], 51, "flat"),
	"car_truck_green": lambda: truck("car_truck_green", P["olive"], 52, "tent"),
	"car_truck_logs": lambda: truck("car_truck_logs", P["darkgreen"], 53, "logs"),
	"car_fire": lambda: truck("car_fire", P["red"], 54, "tank"),
	"tractor_blue": lambda: tractor("tractor_blue", P["mtzblue"], 61),
	"tractor_red": lambda: tractor("tractor_red", P["red"], 62),
}

if __name__ == "__main__":
	OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/cars"
	os.makedirs(OUT, exist_ok=True)
	only = [x for x in os.environ.get("ONLY", "").split(",") if x]
	bpy.ops.wm.read_factory_settings(use_empty=True)
	objs = []
	i = 0
	cols = int(os.environ.get("COLS", "6"))
	for n, fn in JOBS.items():
		if only and n not in only:
			continue
		o = fn()
		o.location = ((i % cols) * 6.5, -(i // cols) * 5.0, 0)
		i += 1
		objs.append(o)
		print("CAR %-22s %5d тр. %.2f x %.2f x %.2f м" % (n, sum(len(p.vertices) - 2 for p in o.data.polygons), o.dimensions.x, o.dimensions.y, o.dimensions.z), flush=True)
	if os.environ.get("SHOW", "1") == "1":
		H.preview(objs, os.path.join(OUT, "cars.png"), persp=os.environ.get("PERSP") == "1", pad=5.0, dist_k=0.85, elev=28, samples=48)
