# Анимации героя ключевыми кадрами на его скелете (hero.py). Повороты задаются в осях арматуры в покое
# (X — вправо персонажа влево… см. ниже), «относительно родителя»: согнул плечо — предплечье идёт следом.
# Оси: персонаж смотрит в −Y; +X — его левая сторона; +Z — вверх.
#   колено сгибается: Leg  +X;   бедро вперёд: UpLeg −X;   корпус вперёд: Spine* +X;
#   рука вперёд: Arm −X;  локоть (кисть к лицу): ForeArm −X;  левая рука ниже к боку: LeftArm +Y, правая −Y;  голова влево: Head +Z
# Клипы (30 кадр/с): Idle, Walk, Run, Lie, WakeUp, SitChair, LieLounger, Phone, Scared, ClimbDown, ClimbUp.
import bpy, math
from mathutils import Quaternion, Vector, Matrix

FPS = 30
AX = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}

def q_arm(rots):
	q = Quaternion()
	for a, deg in rots:
		q = Quaternion(AX[a], math.radians(deg)) @ q
	return q

ARMS_DOWN = {"LeftArm": [("Y", 20)], "RightArm": [("Y", -20)], "LeftForeArm": [("X", -10)], "RightForeArm": [("X", -10)]}

def pose(**kw):
	"""Поза: bone → [(ось, градусы)…]; спец. ключ 'hips' → (dx, dy, dz) метры (смещение таза)."""
	p = {k: list(v) for k, v in ARMS_DOWN.items()}
	for k, v in kw.items():
		if k == "hips":
			p["hips"] = v
		else:
			p[k] = p.get(k, []) + list(v)
	return p

def lerp_pose(a, b, t):
	"""Смешать две позы (кватернионы — slerp)."""
	out = {}
	for k in set(a) | set(b):
		if k == "hips":
			va = Vector(a.get("hips", (0, 0, 0))); vb = Vector(b.get("hips", (0, 0, 0)))
			out["hips"] = tuple(va.lerp(vb, t))
		else:
			out[k] = ("Q", q_arm(a.get(k, [])).slerp(q_arm(b.get(k, [])), t))
	return out

def apply(rig, P, frame):
	for pb in rig.pose.bones:
		R = rig.data.bones[pb.name].matrix_local.to_quaternion()
		v = P.get(pb.name)
		if v is None:
			qa = Quaternion()
		elif isinstance(v, tuple) and v and v[0] == "Q":
			qa = v[1]
		else:
			qa = q_arm(v)
		pb.rotation_mode = "QUATERNION"
		pb.rotation_quaternion = R.inverted() @ qa @ R
		pb.keyframe_insert("rotation_quaternion", frame=frame)
		if pb.name == "Hips":
			d = Vector(P.get("hips", (0, 0, 0)))
			pb.location = R.inverted() @ d
			pb.keyframe_insert("location", frame=frame)

def clip(rig, name, keys, loop=False):
	"""keys: [(секунды, поза)] → действие name в NLA (каждое — отдельная анимация в glTF)."""
	act = bpy.data.actions.new(name)
	rig.animation_data_create()
	rig.animation_data.action = act
	for t, P in keys:
		apply(rig, P if any(isinstance(v, tuple) and v and v[0] == "Q" for v in P.values()) else P, int(round(t * FPS)) + 1)
	tr = rig.animation_data.nla_tracks.new(); tr.name = name
	st = tr.strips.new(name, 1, act)
	rig.animation_data.action = None
	return act

def cycle(fn, period, n=8):
	"""Цикл из функции фазы fn(ф 0..1) → поза; n ключей + повтор первого."""
	return [(period * i / n, fn(i / n)) for i in range(n)] + [(period, fn(0.0))]

def make(rig):
	s = math.sin
	TAU = 2 * math.pi
	stand = pose()
	# стоит, дышит
	clip(rig, "Idle", cycle(lambda f: pose(Spine2=[("X", 1.5 * s(TAU * f))], Head=[("X", -1 * s(TAU * f))], hips=(0, 0, 0.004 * s(TAU * f))), 3.0, 6))
	# шаг (1,1 с на два шага)
	def walk(f):
		a = s(TAU * f)
		kL = max(0.0, s(TAU * f + 1.9)) * 45 + 5
		kR = max(0.0, s(TAU * f + 1.9 + math.pi)) * 45 + 5
		return pose(LeftUpLeg=[("X", -24 * a)], RightUpLeg=[("X", 24 * a)], LeftLeg=[("X", kL)], RightLeg=[("X", kR)],
			LeftFoot=[("X", -8 * a)], RightFoot=[("X", 8 * a)],
			LeftArm=[("X", 18 * a)], RightArm=[("X", -18 * a)], LeftForeArm=[("X", -15)], RightForeArm=[("X", -15)],
			Spine=[("Z", 4 * a)], Spine2=[("Z", -6 * a), ("X", 3)], hips=(0.012 * a, 0, -0.02 + 0.015 * abs(s(TAU * f))))
	clip(rig, "Walk", cycle(walk, 1.1, 12))
	# бег (0,7 с)
	def run(f):
		a = s(TAU * f)
		kL = max(0.0, s(TAU * f + 1.6)) * 95 + 15
		kR = max(0.0, s(TAU * f + 1.6 + math.pi)) * 95 + 15
		return pose(LeftUpLeg=[("X", -45 * a - 10)], RightUpLeg=[("X", 45 * a - 10)], LeftLeg=[("X", kL)], RightLeg=[("X", kR)],
			LeftArm=[("X", 40 * a), ("Y", -10)], RightArm=[("X", -40 * a), ("Y", 10)], LeftForeArm=[("X", -85)], RightForeArm=[("X", -85)],
			Spine=[("X", 10), ("Z", 6 * a)], Spine2=[("X", 4), ("Z", -10 * a)], Head=[("X", -10)],
			hips=(0, 0, -0.05 + 0.04 * abs(s(TAU * f))))
	clip(rig, "Run", cycle(run, 0.7, 12))
	# лёжа на спине (голова к +Y, лицо вверх); таз опускается к постели
	lie = pose(Hips=[("X", -90)], LeftArm=[("Y", 15)], RightArm=[("Y", -15)], LeftForeArm=[("X", 10)], RightForeArm=[("X", 10)],
		LeftUpLeg=[("X", -4)], RightUpLeg=[("X", -4)], LeftLeg=[("X", 6)], RightLeg=[("X", 6)], Head=[("X", 10)], hips=(0, 0.0, -0.84))
	breath = lambda P, f: lerp_pose(P, pose(**{**{k: v for k, v in P.items() if k != "hips"}, "Spine2": P.get("Spine2", []) + [("X", 2)]}, **({"hips": P["hips"]} if "hips" in P else {})), 0.5 + 0.5 * s(TAU * f))
	clip(rig, "Lie", [(0, lie), (2.0, lie)])
	# просыпается: сел (ноги вперёд) → сел на край (ноги вниз) → встал
	sit_up = pose(Hips=[("X", -10)], LeftUpLeg=[("X", -80)], RightUpLeg=[("X", -80)], LeftLeg=[("X", 5)], RightLeg=[("X", 5)],
		Spine=[("X", 12)], LeftArm=[("Y", 10), ("X", -15)], RightArm=[("Y", -10), ("X", -15)], LeftForeArm=[("X", -40)], RightForeArm=[("X", -60)],
		Head=[("X", 8)], hips=(0, 0.25, -0.5))
	stretch = pose(Hips=[("X", -10)], LeftUpLeg=[("X", -80)], RightUpLeg=[("X", -80)], Spine=[("X", -5)], Spine2=[("X", -8)],
		LeftArm=[("Y", -80), ("X", -40)], RightArm=[("Y", 80), ("X", -40)], LeftForeArm=[("X", -20)], RightForeArm=[("X", -20)], Head=[("X", -15)], hips=(0, 0.25, -0.5))
	edge = pose(LeftUpLeg=[("X", -85)], RightUpLeg=[("X", -85)], LeftLeg=[("X", 85)], RightLeg=[("X", 85)], Spine=[("X", 15)],
		LeftArm=[("X", -20)], RightArm=[("X", -20)], LeftForeArm=[("X", -30)], RightForeArm=[("X", -30)], hips=(0, 0.1, -0.45))
	clip(rig, "WakeUp", [(0, lie), (0.6, lie), (1.6, sit_up), (2.4, stretch), (3.2, sit_up), (3.8, edge), (4.6, pose(Spine=[("X", 25)], LeftUpLeg=[("X", -40)], RightUpLeg=[("X", -40)], LeftLeg=[("X", 50)], RightLeg=[("X", 50)], hips=(0, 0.05, -0.2))), (5.4, stand)])
	# сидит на стуле, руки на бёдрах, смотрит вдаль
	sit = pose(LeftUpLeg=[("X", -88)], RightUpLeg=[("X", -88)], LeftLeg=[("X", 88)], RightLeg=[("X", 88)], Spine=[("X", -4)],
		LeftArm=[("X", -12), ("Y", 8)], RightArm=[("X", -12), ("Y", -8)], LeftForeArm=[("X", -55)], RightForeArm=[("X", -55)], hips=(0, 0.04, -0.47))
	clip(rig, "SitChair", cycle(lambda f: lerp_pose(sit, pose(**{**{k: v for k, v in sit.items() if k != "hips"}, "Head": [("Z", 12)]}, hips=sit["hips"]), 0.5 + 0.5 * s(TAU * f)), 6.0, 6))
	# шезлонг: спина приподнята на 40°, ноги вытянуты
	lounge = pose(Hips=[("X", -55)], LeftUpLeg=[("X", -35)], RightUpLeg=[("X", -35)], LeftLeg=[("X", 8)], RightLeg=[("X", 8)],
		LeftArm=[("Y", 10)], RightArm=[("Y", -10)], LeftForeArm=[("X", -40)], RightForeArm=[("X", -40)], Head=[("X", 15)], hips=(0, 0.25, -0.68))
	clip(rig, "LieLounger", cycle(lambda f: lerp_pose(lounge, pose(**{**{k: v for k, v in lounge.items() if k != "hips"}, "Spine2": [("X", 2)]}, hips=lounge["hips"]), 0.5 + 0.5 * s(TAU * f)), 4.0, 4))
	# телефон: правая рука поднята, телефон перед лицом, голова наклонена к нему
	phone = pose(**{**{k: v for k, v in lounge.items() if k not in ("hips", "RightArm", "RightForeArm", "Head")}},
		RightArm=[("Y", -5), ("X", -75)], RightForeArm=[("X", -95), ("Z", 15)], RightHand=[("X", 20)], Head=[("X", 28)], hips=lounge["hips"])
	clip(rig, "Phone", [(0, lounge), (1.0, phone), (4.0, lerp_pose(phone, pose(**{**{k: v for k, v in phone.items() if k not in ("hips", "Head")}}, Head=[("X", 35)], hips=phone["hips"]), 1.0))])
	# испуг: резко сел, вскочил
	alarm = pose(LeftUpLeg=[("X", -70)], RightUpLeg=[("X", -70)], LeftLeg=[("X", 70)], RightLeg=[("X", 70)], Spine=[("X", 25)],
		RightArm=[("X", -60)], RightForeArm=[("X", -90)], LeftArm=[("X", -30), ("Y", 20)], Head=[("X", 5)], hips=(0, 0.1, -0.4))
	clip(rig, "Scared", [(0, phone), (0.35, alarm), (0.9, pose(Spine=[("X", 10)], RightArm=[("X", -20)], RightForeArm=[("X", -60)], hips=(0, 0, -0.05))), (1.3, stand)])
	# спуск в люк: присел, ухватился, ушёл вниз (таз −1,9 м); подъём — обратно
	crouch = pose(LeftUpLeg=[("X", -100)], RightUpLeg=[("X", -100)], LeftLeg=[("X", 120)], RightLeg=[("X", 120)], Spine=[("X", 35)],
		LeftArm=[("X", -60)], RightArm=[("X", -60)], LeftForeArm=[("X", -20)], RightForeArm=[("X", -20)], hips=(0, 0.05, -0.55))
	hang = pose(LeftUpLeg=[("X", -30)], RightUpLeg=[("X", -15)], LeftLeg=[("X", 50)], RightLeg=[("X", 30)], Spine=[("X", 10)],
		LeftArm=[("X", -150)], RightArm=[("X", -150)], LeftForeArm=[("X", -10)], RightForeArm=[("X", -10)], hips=(0, -0.15, -1.0))
	down = pose(LeftUpLeg=[("X", -20)], RightUpLeg=[("X", -40)], LeftLeg=[("X", 30)], RightLeg=[("X", 60)],
		LeftArm=[("X", -170)], RightArm=[("X", -160)], hips=(0, -0.1, -1.95))
	clip(rig, "ClimbDown", [(0, stand), (0.6, crouch), (1.3, hang), (2.6, down)])
	clip(rig, "ClimbUp", [(0, down), (1.3, hang), (2.0, crouch), (2.6, stand)])
	return rig
