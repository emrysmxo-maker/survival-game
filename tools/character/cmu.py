# Мокап CMU Graphics Lab (http://mocap.cs.cmu.edu, ASF/AMC, свободно для любого использования) → скелет героя.
# Разбор ASF/AMC, прямая кинематика, перенос на арматуру Blender по мировым поворотам костей:
#   мировой поворот кости цели = (поворот источника от покоя) × (выравнивание направлений костей в покое) × (покой цели).
# Источник: Y — вверх, лицо в +Z, левая сторона +X, покой — Т-поза. Цель (герой): Z — вверх, лицо в −Y, левая +X.
# Скачать записи: bash tools/character/get_cmu.sh  (в /tmp/claude-0/cmu_dl/data)
import math, re
import numpy as np
from mathutils import Quaternion, Matrix, Vector, Euler

Q_SRC = Quaternion((1, 0, 0), math.radians(90))                     # источник → цель: Y вверх → Z вверх, +Z → −Y

def _euler(vals, order):
	"""Углы (градусы) в порядке order ('XYZ'…) → матрица: поворот сначала по первой оси."""
	m = Matrix.Identity(3)
	for a, v in zip(order, vals):
		m = Matrix.Rotation(math.radians(v), 3, a) @ m
	return m

class Skel:
	def __init__(self, path):
		t = open(path, encoding="latin1").read()
		self.unit = 1.0
		m = re.search(r":units(.*?):", t, re.S)
		if m:
			for ln in m.group(1).split("\n"):
				p = ln.split()
				if len(p) == 2 and p[0] == "length":
					self.unit = float(p[1])
		self.bones = {}
		for blk in re.findall(r"begin(.*?)end", t.split(":bonedata")[1].split(":hierarchy")[0], re.S):
			b = {"dof": []}
			for ln in blk.strip().split("\n"):
				p = ln.split()
				if not p:
					continue
				if p[0] == "name":
					b["name"] = p[1]
				elif p[0] == "direction":
					b["dir"] = Vector([float(x) for x in p[1:4]])
				elif p[0] == "length":
					b["len"] = float(p[1])
				elif p[0] == "axis":
					b["C"] = _euler([float(x) for x in p[1:4]], p[4].upper())
				elif p[0] == "dof":
					b["dof"] = [x.lower() for x in p[1:]]
			self.bones[b["name"]] = b
		self.parent = {}
		self.order = ["root"]
		for ln in t.split(":hierarchy")[1].split("begin")[1].split("end")[0].strip().split("\n"):
			p = ln.split()
			for c in p[1:]:
				self.parent[c] = p[0]
				self.order.append(c)
		m = re.search(r":root(.*?):bonedata", t, re.S).group(1)
		ax = re.search(r"axis\s+(\w+)", m).group(1).upper()
		ori = [float(x) for x in re.search(r"orientation\s+([-\d.e ]+)", m).group(1).split()]
		self.rootC = _euler(ori, ax)
		self.rootorder = re.search(r"order\s+(.*)", m).group(1).lower().split()

	def fk(self, fr):
		"""Кадр AMC (имя → значения) → (S: имя → Quaternion поворот от покоя, P: имя → начало кости, E: конец)."""
		r = fr["root"]
		dv = dict(zip(self.rootorder, r))
		pos = Vector((dv.get("tx", 0), dv.get("ty", 0), dv.get("tz", 0)))
		M = _euler([dv.get("rx", 0), dv.get("ry", 0), dv.get("rz", 0)], "XYZ")
		S = {"root": (self.rootC @ M @ self.rootC.inverted())}
		P = {"root": pos}; E = {"root": pos}
		for n in self.order[1:]:
			b = self.bones[n]
			vals = fr.get(n, [])
			ang = {"rx": 0.0, "ry": 0.0, "rz": 0.0}
			for d, v in zip(b["dof"], vals):
				ang[d] = v
			M = _euler([ang["rx"], ang["ry"], ang["rz"]], "XYZ")
			L = b["C"] @ M @ b["C"].inverted()
			S[n] = S[self.parent[n]] @ L
			P[n] = E[self.parent[n]]
			E[n] = P[n] + S[n] @ (b["dir"] * b["len"])
		return {k: v.to_quaternion() for k, v in S.items()}, P, E

def read_amc(path):
	frames, cur = [], None
	for ln in open(path, encoding="latin1"):
		ln = ln.strip()
		if not ln or ln[0] in "#:":
			continue
		if ln.isdigit():
			cur = {}; frames.append(cur)
			continue
		p = ln.split()
		cur[p[0]] = [float(x) for x in p[1:]]
	return frames

# кость героя: (кость CMU — поворот, кость CMU — направление в покое)
MAP = {
	"Hips": ("root", "lowerback"), "Spine": ("lowerback", "lowerback"), "Spine1": ("upperback", "upperback"),
	"Spine2": ("thorax", "thorax"), "Neck": ("upperneck", "upperneck"), "Head": ("head", "head"),
}
for s, c in (("Left", "l"), ("Right", "r")):
	MAP.update({s + "Shoulder": (c + "clavicle", c + "clavicle"), s + "Arm": (c + "humerus", c + "humerus"),
		s + "ForeArm": (c + "radius", c + "radius"), s + "Hand": (c + "hand", c + "hand"),
		s + "UpLeg": (c + "femur", c + "femur"), s + "Leg": (c + "tibia", c + "tibia"),
		s + "Foot": (c + "foot", c + "foot"), s + "ToeBase": (c + "toes", c + "toes")})

def minarc(a, b):
	"""Кратчайший поворот направления a в направление b."""
	return a.normalized().rotation_difference(b.normalized())

class Take:
	"""Запись: кадры 120 Гц → повороты/точки в осях цели (с поправкой курса)."""
	def __init__(self, skel, amc_path, fps=120):
		self.sk = skel
		self.fps = fps
		self.raw = read_amc(amc_path)
		self.S, self.P, self.E = [], [], []
		for fr in self.raw:
			S, P, E = skel.fk(fr)
			self.S.append(S); self.P.append(P); self.E.append(E)
		self.n = len(self.raw)

	def dur(self):
		return self.n / self.fps

	def facing(self, f):
		"""Курс (рад, вокруг вертикали источника): куда смотрит таз; 0 — в +Z."""
		left = self.P[f]["lfemur"] - self.P[f]["rfemur"]
		fw = left.cross(Vector((0, 1, 0)))
		return math.atan2(fw.x, fw.z)

	def foot_y(self, f):
		return min(self.E[f][k].y for k in ("ltoes", "rtoes", "lfoot", "rfoot"))

	def low_y(self, f):
		return min(v.y for v in self.E[f].values())

class Rig:
	"""Покой арматуры цели (пространство арматуры)."""
	def __init__(self, arm_obj):
		self.obj = arm_obj
		self.rest = {}; self.dir = {}; self.parent = {}
		for b in arm_obj.data.bones:
			self.rest[b.name] = b.matrix_local.to_quaternion()
			self.dir[b.name] = (b.tail_local - b.head_local)
			self.parent[b.name] = b.parent.name if b.parent else None
		bb = arm_obj.data.bones
		self.hips = bb["Hips"].head_local.copy()
		self.leg = (bb["RightUpLeg"].head_local - bb["RightFoot"].head_local).length
		self.stand = self.hips.z - min(bb["RightToeBase"].tail_local.z, bb["RightFoot"].head_local.z - 0.06)

def keys(take, rig, f0, f1, mode="anchor", step=4, ground=None, yaw=None, hold_ends=0):
	"""Перенос кадров f0..f1 (каждый step-й) → список поз [(кость → Quaternion базис), положение таза Vector].
	mode: 'anchor' — без ухода по горизонтали и по курсу (точка стоит на месте, мелкие покачивания остаются);
	      'loop'   — цикл: увод и курс разложены линейно, конец = начало;
	      'root'   — движение как есть (относительно начала), курс выровнен по первому кадру."""
	sk = take.sk
	frames = list(range(f0, f1 + 1, step))
	if frames[-1] != f1:
		frames.append(f1)
	n = len(frames)
	yaw0 = take.facing(f0) if yaw is None else yaw
	yaw1 = take.facing(f1)
	dyaw = math.atan2(math.sin(yaw1 - yaw0), math.cos(yaw1 - yaw0))
	if ground is None:
		ground = min(take.foot_y(f) for f in range(f0, f1 + 1))
	k = rig.leg / ((sk.bones["rfemur"]["len"] + sk.bones["rtibia"]["len"]))
	stand_src = take.P[0]["root"].y - take.foot_y(0)                    # не используется для покоя — берём из скелета
	# высота таза над землёй в Т-позе источника
	rest_S = {b: Quaternion() for b in sk.bones}
	e = {"root": Vector()}
	for nm in sk.order[1:]:
		b = sk.bones[nm]
		e[nm] = e[sk.parent[nm]] + b["dir"] * b["len"]
	stand_src = -min(e[x].y for x in ("ltoes", "rtoes", "lfoot", "rfoot"))
	root0 = take.P[f0]["root"].copy(); root1 = take.P[f1]["root"].copy()
	out = []
	prev = {}
	for i, f in enumerate(frames):
		t = i / max(1, n - 1)
		yc = -(yaw0 + (dyaw * t if mode in ("anchor", "loop") else 0.0))
		Ry = Quaternion((0, 1, 0), yc)
		S = take.S[f]
		W = {}
		for tb, (sb, sd) in MAP.items():
			if tb not in rig.rest:
				continue
			src = Q_SRC @ Ry @ S[sb] @ Q_SRC.inverted()
			A = minarc(rig.dir[tb], Q_SRC @ sk.bones[sd]["dir"])
			W[tb] = src @ A @ rig.rest[tb]
		B = {}
		for tb, w in W.items():
			p = rig.parent[tb]
			if p is None:
				q = rig.rest[tb].inverted() @ w
			else:
				q = rig.rest[tb].inverted() @ rig.rest[p] @ W[p].inverted() @ w
			if tb in prev and q.dot(prev[tb]) < 0:
				q.negate()
			prev[tb] = q
			B[tb] = q
		# таз
		r = take.P[f]["root"] - root0
		if mode in ("anchor", "loop"):
			r = r - (root1 - root0) * t
		r = Ry @ Vector((r.x, 0.0, r.z))
		h = (take.P[f]["root"].y - ground - stand_src) * k
		d = Q_SRC @ Vector((r.x * k, 0.0, r.z * k))
		d.z = h
		out.append((B, d))
	if mode == "loop":                                                 # замкнуть повороты: ошибка конец/начало — линейно
		for tb in out[0][0]:
			err = out[-1][0][tb] @ out[0][0][tb].inverted()
			ax, ang = err.to_axis_angle()
			if ang > math.pi:
				ang -= 2 * math.pi
			for i, (B, d) in enumerate(out):
				t = i / max(1, n - 1)
				B[tb] = Quaternion(ax, -ang * t) @ B[tb]
		dz = out[-1][1].z - out[0][1].z
		for i, (B, d) in enumerate(out):
			d.z -= dz * i / max(1, n - 1)
	info = {"yaw_turn": dyaw, "move": (Q_SRC @ (Quaternion((0, 1, 0), -yaw0) @ Vector(((root1 - root0).x, 0, (root1 - root0).z)))) * k,
		"k": k, "frames": n}
	return out, info

def write_action(rig, name, poses, fps_out=30, push_nla=True):
	"""Позы → действие Blender (кадр на позу) в отдельной дорожке NLA."""
	import bpy
	obj = rig.obj
	obj.animation_data_create()
	act = bpy.data.actions.new(name)
	obj.animation_data.action = act
	for i, (B, d) in enumerate(poses):
		for pb in obj.pose.bones:
			if pb.name not in B:
				continue
			pb.rotation_mode = "QUATERNION"
			pb.rotation_quaternion = B[pb.name]
			pb.keyframe_insert("rotation_quaternion", frame=i + 1)
			if pb.name == "Hips":
				pb.location = rig.rest["Hips"].inverted() @ d
				pb.keyframe_insert("location", frame=i + 1)
	if push_nla:
		tr = obj.animation_data.nla_tracks.new(); tr.name = name
		tr.strips.new(name, 1, act)
		obj.animation_data.action = None
	return act

def find_cycle(take, a, b, pmin, pmax):
	"""Лучший цикл в окне кадров a..b: период в [pmin, pmax] с, похожесть поз ног/рук и высоты таза."""
	bones = ["lfemur", "rfemur", "ltibia", "rtibia", "lhumerus", "rhumerus", "lowerback"]
	def feat(f):
		v = []
		for bn in bones:
			v += list(take.S[f][bn] if take.S[f][bn].w >= 0 else -take.S[f][bn])
		return np.array(v)
	F = {f: feat(f) for f in range(a, b + 1)}
	best = None
	for f0 in range(a, b + 1, 2):
		for p in range(int(pmin * take.fps), int(pmax * take.fps) + 1, 2):
			f1 = f0 + p
			if f1 > b:
				break
			d = np.linalg.norm(F[f0] - F[f1]) + 0.5 * np.linalg.norm(F[f0 + 2] - F[f1 + 2] if f1 + 2 <= b else 0)
			if best is None or d < best[0]:
				best = (d, f0, f1)
	return best
