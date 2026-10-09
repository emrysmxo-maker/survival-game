# Анимации героя из мокапа CMU (живой человек, http://mocap.cs.cmu.edu — свободно для любого использования).
# Каждый клип — отрезок записи (секунды), перенесённый на скелет героя (cmu.py), → действие в NLA (отдельная анимация в glTF).
# Режимы: loop — цикл на месте (ходьба/бег/лестница; скорость → hero_clips.json), anchor — стоит на месте,
#         root — движение таза как в записи (смещение и поворот в конце → hero_clips.json, заставка переносит узел).
# Слоистые клипы: верх тела из одной записи, низ — из другой (телефон сидя).
import bpy, json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmu
from mathutils import Vector, Quaternion

DATA = os.environ.get("CMU", "/tmp/claude-0/cmu_dl/data")
UPPER = {"Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"}

# имя: (запись, начало с, конец с, режим, опции)
CLIPS = {
	"Sleep":      ("77_18", 0.05, 0.60, "loop", {}),                  # спит на боку
	"SitIdle":    ("113_15", 2.6, 4.6, "loop", {}),                   # сидит, руки на коленях (край кровати, стул)
	"StandUp":    ("111_09", 2.6, 4.6, "root", {}),                   # встаёт со стула/кровати
	"Stretch":    ("143_30", 0.15, 3.05, "anchor", {}),               # потягивается, зевает
	"Idle":       ("80_25", 0.3, 1.8, "loop", {}),                    # стоит спокойно
	"WashFace":   ("79_90", 0.4, 8.4, "anchor", {}),                  # умывается: ладони к лицу
	"LookAround": ("139_03", 1.0, 8.0, "anchor", {}),                 # оглядывается, смотрит вдаль
	"Walk":       ("07_01", 0.2, 2.5, "cycle", {"p": (0.9, 1.4)}),
	"WalkSlow":   ("07_04", 0.3, 3.6, "cycle", {"p": (1.0, 1.7)}),
	"Run":        ("09_01", 0.05, 1.2, "cycle", {"p": (0.55, 0.9)}),
	"SitDown":    ("143_18", 0.55, 2.2, "root", {}),                  # садится на стул
	"PhoneOut":   ("79_37", 0.7, 2.0, "anchor", {}),                  # достаёт телефон, подносит к глазам (стоя)
	"PhoneRead":  ("79_37", 1.9, 2.8, "loop", {}),                    # читает (стоя)
	"SitPhoneOut": ("79_37", 0.7, 2.0, "anchor", {"low": "SitIdle"}),  # то же сидя
	"SitPhoneRead": ("79_37", 1.9, 2.8, "loop", {"low": "SitIdle"}),
	"ClimbDown":  ("13_33", 7.6, 11.0, "cycle", {"p": (0.9, 2.2), "vert": True}),   # спуск по лестнице (цикл, узел едет вниз)
	"ClimbUp":    ("13_33", 2.4, 6.0, "cycle", {"p": (0.9, 2.2), "vert": True}),
}

_takes = {}
def take(t):
	if t not in _takes:
		sk = cmu.Skel(os.path.join(DATA, t.split("_")[0] + ".asf"))
		_takes[t] = cmu.Take(sk, os.path.join(DATA, t + ".amc"))
	return _takes[t]

def sole(arm):
	"""Высота подошв (м над нулём) в текущем кадре."""
	m = 9.0
	for s in ("Left", "Right"):
		ft = arm.pose.bones[s + "Foot"]; tb = arm.pose.bones[s + "ToeBase"]
		m = min(m, (arm.matrix_world @ tb.tail).z - 0.02, (arm.matrix_world @ ft.head).z - 0.08)
	return m

def make(arm, only=None):
	rig = cmu.Rig(arm)
	sc = bpy.context.scene
	info = {}
	poses_by = {}
	for name, (tr, a, b, mode, o) in CLIPS.items():
		if only and name not in only and name not in [CLIPS[x][4].get("low") for x in only]:
			continue
		tk = take(tr)
		f0, f1 = int(a * tk.fps), min(tk.n - 1, int(b * tk.fps))
		if mode == "cycle":
			d, f0, f1 = cmu.find_cycle(tk, f0, f1, *o["p"])
			mode = "loop"
		poses, inf = cmu.keys(tk, rig, f0, f1, mode=mode)
		if o.get("low"):                                               # низ тела из другого клипа
			low = poses_by[o["low"]]
			for i, (B, d) in enumerate(poses):
				lb, ld = low[i % (len(low) - 1)]
				for k in B:
					if k not in UPPER:
						B[k] = lb[k]
				poses[i] = (B, ld.copy())
		poses_by[name] = poses
		act = cmu.write_action(rig, name, poses, push_nla=False)
		arm.animation_data.action = act
		n = len(poses)
		# земля: подошвы на ноль (лестница — подошвы как есть, узел двигает заставка)
		if not o.get("vert"):
			ss = []
			for fr in range(1, n + 1):
				sc.frame_set(fr); ss.append(sole(arm))
			ss.sort()
			dz = -ss[max(0, int(len(ss) * 0.03))]
			if name == "Sleep":
				dz = -ss[0]
			if abs(dz) > 1e-4:
				arm.animation_data.action = None
				bpy.data.actions.remove(act)
				for B, d in poses:
					d.z += dz
				act = cmu.write_action(rig, name, poses, push_nla=False)
				arm.animation_data.action = act
		dur = (n - 1) / 30.0
		mv = inf["move"]
		row = {"length": round(dur, 3), "src": "%s %.2f-%.2f" % (tr, f0 / tk.fps, f1 / tk.fps)}
		if mode == "loop":
			row["speed"] = round(mv.length / dur, 3) if not o.get("vert") else 0.0
			if o.get("vert"):
				r0 = tk.P[f0]["root"].y; r1 = tk.P[f1]["root"].y
				row["vspeed"] = round((r1 - r0) * inf["k"] / dur, 3)
		if mode == "root":
			row["move"] = [round(mv.x, 3), round(mv.y, 3)]
			row["turn"] = round(math.degrees(inf["yaw_turn"]), 1)
		sc.frame_set(1)                                                # начальная поза: таз и голова (для укладки на кровать)
		hp = arm.matrix_world @ arm.pose.bones["Hips"].head; hd = arm.matrix_world @ arm.pose.bones["Head"].head
		row["hips0"] = [round(hp.x, 3), round(hp.y, 3), round(hp.z, 3)]
		row["head0"] = [round(hd.x, 3), round(hd.y, 3), round(hd.z, 3)]
		info[name] = row
		tr_ = arm.animation_data.nla_tracks.new(); tr_.name = name
		tr_.strips.new(name, 1, act)
		arm.animation_data.action = None
		print("CLIP %-13s %s" % (name, row))
	return info
