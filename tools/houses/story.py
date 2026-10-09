# Модели для сюжета (заставка «как всё началось»): дом героя у озера с верандой, сарай с люком в самодельный бункер,
# крышка люка (отдельно — открывается в игре), шезлонг, садовые стул и столик, телефон; лаборатория «НИИ «Вектор-7»»
# (главный корпус, крыло, труба, резервуар, щиты «Биологическая опасность»); вертолёт и истребитель в полёте (винт отдельно).
# Строится теми же средствами, что дома (house.py: HB, mat, house, фото-текстуры).
import zlib, bpy, math, random, sys, os
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import house as H
from house import HB, mat, house, text_mesh, W
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "cars"))
import car as C
import places as P

H.FLAT.update({"steel": ((0.36, 0.38, 0.36), 0.45, 0.85), "steel_dark": ((0.18, 0.19, 0.19), 0.5, 0.8),
	"hazard": ((0.95, 0.75, 0.10), 0.6, 0.0), "lab_white": ((0.86, 0.86, 0.83), 0.8, 0.0)})

# ---------------- дом героя ----------------
def hero_house(name):
	"""Дом у озера: брус, металлочерепица, большие окна к воде; сзади (+Y, к озеру) — веранда-терраса с навесом и перилами."""
	spec = dict(L=9.0, D=8.0, wall="planks_brown", wcol=(1.0, 0.95, 0.88), t=0.25, h=2.8, plinth=0.6, plinth_mat="concrete", roof="gable", rmat="profnastil",
		rcol=(0.30, 0.42, 0.36), pitch=28, inner="paint_wall", icol=(0.95, 0.93, 0.86), floor="floor_wood",
		front=W(-1.8, 0.8, 2.8, w=1.3, h=1.4), back=W(-2.6, -0.6, 1.6, w=1.6, h=1.8), left=W(-1.5, 1.5, w=1.3, h=1.4), right=W(0.0, w=1.3, h=1.4),
		door=(-3.4, 1.0), door_kind="wood", porch=dict(w=2.0, d=1.4, roof=True), chimney=(1.6, 1.2), pvc=True, frame="frame_white",
		rooms=[("y", 0.6, -3.75, 3.75, 1.5), ("x", 0.4, -4.25, 0.6, -2.0)], state="ok", extras=["dish", "downpipe"], gable_mat="planks_brown", furnish=False)
	sh, rf = house(name, spec, 41)
	hb = HB()
	# мебель на известных местах (по ним идёт заставка): спальня справа, гостиная и кухня слева
	rnd = random.Random(3)
	z = 0.6 + 0.04
	H.f_bed(H._Pose(hb, 2.6, 3.25, z, math.pi), rnd, 2.0, 0.95, False)              # кровать у задней стены, изголовье к +X
	H.f_wardrobe(H._Pose(hb, 3.75, -1.0, z, math.pi / 2), rnd, 1.0, 0.58, False)
	H.f_sofa(H._Pose(hb, -2.4, 3.3, z, math.pi), rnd, 1.9, 0.85, False)
	H.f_tv(H._Pose(hb, -2.4, 0.9, z, 0.0), rnd, 1.0, 0.45, False)
	H.f_sideboard(H._Pose(hb, -4.25 + 0.25 + 0.23, 2.0, z, -math.pi / 2), rnd, 1.6, 0.45, False)
	H.f_kitchen(H._Pose(hb, -2.6, -3.75 + 0.28 + 0.3, z, 0.0), rnd, 2.0, 0.6, False)
	H.f_fridge(H._Pose(hb, -0.6, -3.75 + 0.28 + 0.31, z, 0.0), rnd, 0.6, 0.62, False)
	D, L, zp = 8.0, 9.0, 0.6
	y0, y1 = D / 2, D / 2 + 3.2
	hb.box(mat("floor_wood"), (0, (y0 + y1) / 2, zp - 0.05), (L + 0.4, y1 - y0, 0.1), (0.85, 0.75, 0.62))          # настил
	for x in (-L / 2, -L / 6, L / 6, L / 2):
		hb.box(mat("frame_wood"), (x, y1 - 0.1, zp / 2), (0.15, 0.15, zp), (0.8, 0.8, 0.8))                         # опоры
		hb.box(mat("frame_wood"), (x, y1 - 0.1, zp + 1.3), (0.12, 0.12, 2.6), (0.8, 0.8, 0.8))                      # стойки навеса
	hb.box(mat("profnastil"), (0, (y0 + y1) / 2, zp + 2.75), (L + 0.6, y1 - y0 + 0.5, 0.05), (0.30, 0.42, 0.36), rot=(-0.12, 0, 0))   # навес
	for sx in (-1, 1):                                                                                                  # перила по бокам
		hb.box(mat("frame_wood"), (sx * (L / 2 + 0.15), (y0 + y1) / 2, zp + 0.95), (0.06, y1 - y0, 0.07), (0.8, 0.8, 0.8))
		for k in range(5):
			hb.box(mat("frame_wood"), (sx * (L / 2 + 0.15), y0 + 0.3 + k * 0.65, zp + 0.48), (0.04, 0.04, 0.95), (0.8, 0.8, 0.8))
	for x in (-L / 2 + 0.3, L / 2 - 2.6):                                                                               # перила к озеру (проход посередине)
		hb.box(mat("frame_wood"), (x + 1.15, y1 + 0.05, zp + 0.95), (2.3, 0.06, 0.07), (0.8, 0.8, 0.8))
	for k in range(4):                                                                                                  # ступени к воде
		hb.box(mat("floor_wood"), (0.0, y1 + 0.2 + k * 0.3, zp - 0.15 - k * 0.15), (1.8, 0.3, 0.1), (0.85, 0.75, 0.62))
	_chair_geo(hb, 1.5, 5.6, zp, math.pi)                                                             # стул на веранде лицом к озеру
	hb.cyl(mat("frame_wood"), (2.6, 5.6, zp + 0.72), 0.45, 0.04, "Z", 16, col=(0.6, 0.47, 0.33))      # столик с кружкой
	hb.cyl(mat("frame_wood"), (2.6, 5.6, zp + 0.36), 0.04, 0.72, "Z", 8, col=(0.5, 0.4, 0.3))
	hb.cyl(mat("glass"), (2.75, 5.7, zp + 0.8), 0.04, 0.12, "Z", 10, col=(0.6, 0.6, 0.6))
	v = hb.build(name + "_v")
	return P._join(sh, v, name), rf

def _chair_geo(hb, x, y, z, a):
	"""Садовый стул в точке (x, y, z), повёрнут на a (спинка — в +Y при a=0)."""
	wc = (0.55, 0.42, 0.3)
	c, s_ = math.cos(a), math.sin(a)
	def q(lx, ly, lz):
		return (x + lx * c - ly * s_, y + lx * s_ + ly * c, z + lz)
	hb.box(mat("frame_wood"), q(0, 0, 0.45), (0.5, 0.48, 0.05), wc, rot=(0, 0, a))
	hb.box(mat("frame_wood"), q(0, 0.24, 0.8), (0.5, 0.05, 0.6), wc, rot=(0.15, 0, a))
	for sx in (-0.22, 0.22):
		for sy in (-0.2, 0.2):
			hb.box(mat("frame_wood"), q(sx, sy, 0.22), (0.05, 0.05, 0.45), wc, rot=(0, 0, a))
		hb.box(mat("frame_wood"), q(sx, 0.0, 0.66), (0.05, 0.45, 0.04), wc, rot=(0, 0, a))

def hero_shed(name):
	"""Сарай из досок 4×3,4 м, дверь распахнута; в полу — бетонный оголовок самодельного бункера: люк (проём), лестница вниз."""
	spec = dict(L=4.0, D=3.4, wall="planks_peel", t=0.12, h=2.3, plinth=0.35, plinth_mat="concrete", roof="gable", rmat="tin_rust", rcol=(0.9, 0.9, 0.9),
		pitch=24, inner="planks_brown", lining=False, floor="floor_wood", front=[], back=W(0.0, w=0.6, h=0.5), left=W(0.0, w=0.6, h=0.5), right=[],
		door=(-0.9, 1.1), door_open=1.0, rooms=[], state="ok", furnish=False)
	sh, rf = house(name, spec, 43)
	hb = HB()
	zp = 0.35
	hx, hy = 0.7, 0.35                                                       # оголовок у задней стены
	hb.box(mat("concrete"), (hx, hy, zp + 0.08), (1.3, 1.3, 0.16), (0.7, 0.7, 0.68))
	hb.box(mat("dark"), (hx, hy, zp + 0.161), (0.85, 0.85, 0.01))            # чёрный проём
	for k in range(3):                                                       # верх лестницы в проёме
		hb.box(mat("steel"), (hx, hy + 0.36, zp + 0.1 - k * 0.3), (0.6, 0.03, 0.03), (0.8, 0.8, 0.8))
	for sx in (-1, 1):
		hb.box(mat("steel"), (hx + sx * 0.3, hy + 0.37, zp - 0.2), (0.04, 0.04, 0.8), (0.8, 0.8, 0.8))
	hb.box(mat("steel_dark"), (hx, hy - 0.62, zp + 0.2), (0.9, 0.06, 0.06))                   # петля крышки
	# хозяйство сарая: верстак, канистры, лопата, мешки
	hb.box(mat("frame_wood"), (-1.2, 1.2, zp + 0.45), (1.4, 0.6, 0.9), (0.8, 0.7, 0.6))
	for k in range(3):
		hb.box(mat("metal_paint"), (-1.6 + k * 0.35, -1.2, zp + 0.22), (0.3, 0.18, 0.44), (0.25, 0.42, 0.25))
	hb.beam(mat("frame_wood"), (1.7, -1.4, zp), (1.75, -1.35, zp + 1.5), 0.04)
	for k in range(2):
		hb.box(mat("fabric"), (-0.2 + k * 0.5, -1.3, zp + 0.18), (0.45, 0.3, 0.36), (0.75, 0.68, 0.5), rot=(0, 0, 0.2 * k))
	inner = hb.build(name + "_in")
	return P._join(sh, inner, name), rf

def bunker_lid(name):
	"""Крышка люка: стальной лист 0,9×0,9 с рёбрами и ручкой; петля — по оси X в начале координат (крышка лежит в +Y)."""
	hb = HB()
	hb.box(mat("steel"), (0, 0.45, 0.025), (0.9, 0.9, 0.05), (0.8, 0.8, 0.8))
	for k in (-0.25, 0.0, 0.25):
		hb.box(mat("steel_dark"), (k, 0.45, 0.06), (0.04, 0.85, 0.03))
	hb.box(mat("steel_dark"), (0, 0.8, 0.1), (0.3, 0.04, 0.04))
	hb.box(mat("hazard"), (0, 0.2, 0.052), (0.6, 0.1, 0.003))
	return hb.build(name), None

def lounger(name):
	hb = HB()
	wc = (0.62, 0.48, 0.34)
	for sx in (-0.3, 0.3):
		hb.beam(mat("frame_wood"), (sx, 0.9, 0.35), (sx, -0.6, 0.3), 0.05)
		hb.beam(mat("frame_wood"), (sx, -0.6, 0.3), (sx, -1.0, 0.85), 0.05)
		for y in (0.85, -0.55):
			hb.beam(mat("frame_wood"), (sx, y, 0.0), (sx, y, 0.33), 0.05)
	hb.box(mat("fabric"), (0, 0.15, 0.36), (0.58, 1.5, 0.05), (0.25, 0.42, 0.62))
	hb.box(mat("fabric"), (0, -0.8, 0.6), (0.58, 0.55, 0.05), (0.25, 0.42, 0.62), rot=(-1.0, 0, 0))
	return hb.build(name), None

def garden_chair(name):
	hb = HB()
	wc = (0.55, 0.42, 0.3)
	hb.box(mat("frame_wood"), (0, 0, 0.45), (0.5, 0.48, 0.05), wc)
	hb.box(mat("frame_wood"), (0, 0.24, 0.8), (0.5, 0.05, 0.6), wc, rot=(0.15, 0, 0))
	for sx in (-0.22, 0.22):
		for sy in (-0.2, 0.2):
			hb.box(mat("frame_wood"), (sx, sy, 0.22), (0.05, 0.05, 0.45), wc)
		hb.box(mat("frame_wood"), (sx, 0.0, 0.66), (0.05, 0.45, 0.04), wc)
	return hb.build(name), None

def garden_table(name):
	hb = HB()
	hb.cyl(mat("frame_wood"), (0, 0, 0.72), 0.45, 0.04, "Z", 16, col=(0.6, 0.47, 0.33))
	hb.cyl(mat("frame_wood"), (0, 0, 0.36), 0.04, 0.72, "Z", 8, col=(0.5, 0.4, 0.3))
	hb.cyl(mat("frame_wood"), (0, 0, 0.02), 0.25, 0.04, "Z", 12, col=(0.5, 0.4, 0.3))
	hb.cyl(mat("glass"), (0.15, 0.1, 0.8), 0.04, 0.12, "Z", 10, col=(0.6, 0.6, 0.6))     # кружка
	return hb.build(name), None

def phone(name):
	hb = HB()
	hb.box(mat("steel_dark"), (0, 0, 0), (0.075, 0.155, 0.008), (0.6, 0.6, 0.6))
	hb.box(mat("glass_lit"), (0, 0, 0.0042), (0.068, 0.145, 0.001), (0.6, 0.8, 1.0))
	return hb.build(name), None

# ---------------- лаборатория ----------------
def lab_main(name):
	xs = [-16.0 + i * 2.6 for i in range(13)]
	spec = dict(L=36.0, D=14.0, wall="plaster_white", t=0.4, h=3.4, floors=3, plinth=0.6, plinth_mat="concrete", pcol=(0.6, 0.6, 0.6), roof="hip", rmat="profnastil",
		rcol=(0.55, 0.57, 0.58), pitch=4, inner="paint_wall", icol=(0.85, 0.92, 0.92), floor="linoleum",
		front=[(x, 1.6, 1.6) for x in xs if abs(x - 0.4) > 1.5], front2=[(x, 1.6, 1.6) for x in xs], back=[(x, 1.6, 1.6) for x in xs],
		left=W(-4.0, 0.0, 4.0, w=1.6, h=1.6), right=W(-4.0, 0.0, 4.0, w=1.6, h=1.6), door=(0.4, 2.4), door_kind="metal",
		porch=dict(w=6.0, d=3.0, roof=True, mat="concrete"), pvc=True, frame="frame_white", state="broken",
		rooms=[("x", 1.2, -17.6, 17.6, -8.0), ("y", -8.0, 1.2, 6.6, 3.0), ("y", 8.0, 1.2, 6.6, 3.0)], extras=["downpipe", "ac"], sign_x=0.4, furnish=False)
	ob, rf = P.signed(name, spec, 51, "НИИ «ВЕКТОР-7»", 0.75, (0.88, 0.9, 0.9), (0.15, 0.25, 0.45))
	hb = HB()
	H_ = 0.6 + 3 * 3.4 + 0.6
	for x in (-12.0, -4.0, 6.0, 13.0):                                       # вентиляция и короба на крыше
		hb.box(mat("metal_paint"), (x, 2.0, H_ + 0.9), (2.4, 2.0, 1.6), (0.75, 0.76, 0.76))
		hb.cyl(mat("metal_paint"), (x, -2.0, H_ + 0.9), 0.5, 1.6, "Z", 12, col=(0.7, 0.7, 0.7))
	hb.box(mat("hazard"), (-8.0, -7.1, 2.0), (2.0, 0.05, 1.4), (1, 1, 1))     # знак у входа
	text_mesh(hb, "spray", "ОПАСНО", 0.32, (-8.0, -7.14, 2.15), (0.1, 0.1, 0.1))
	text_mesh(hb, "spray", "БИОЛОГИЯ", 0.22, (-8.0, -7.14, 1.75), (0.1, 0.1, 0.1))
	r2 = hb.build(name + "_x")
	r2.location = (0, 0, 0)
	return P._join(ob, r2, name), rf

def lab_wing(name):
	xs = [-10.0 + i * 2.5 for i in range(9)]
	return house(name, dict(L=24.0, D=10.0, wall="concrete", t=0.4, h=4.0, plinth=0.3, plinth_mat="concrete", roof="hip", rmat="profnastil", rcol=(0.5, 0.52, 0.53), pitch=4,
		inner="paint_wall", icol=(0.9, 0.95, 0.95), floor="linoleum", front=[(x, 1.4, 1.0) for x in xs if abs(x) > 1.5], back=[(x, 1.4, 1.0) for x in xs],
		left=[], right=W(0.0, w=1.4, h=1.0), door=(0.0, 3.0), door_kind="metal", frame="frame_white", sill=2.2, state="broken", rooms=[], furnish=False), 52)

def lab_stack(name):
	hb = HB()
	for k in range(10):
		col = (0.85, 0.15, 0.1) if k % 2 == 0 else (0.92, 0.92, 0.9)
		hb.cyl(mat("metal_paint"), (0, 0, 1.2 + k * 2.4), 1.0 - k * 0.03, 2.4, "Z", 16, col=col)
	hb.box(mat("concrete"), (0, 0, 0.6), (3.0, 3.0, 1.2), (0.7, 0.7, 0.7))
	for k in range(12):                                                        # скобы-лестница
		hb.box(mat("steel"), (0, -1.0, 2.0 + k * 1.8), (0.4, 0.06, 0.04), (0.8, 0.8, 0.8))
	return hb.build(name), None

def lab_tank(name):
	hb = HB()
	hb.cyl(mat("metal_paint"), (0, 0, 4.0), 2.6, 7.0, "Z", 20, col=(0.85, 0.86, 0.85))
	hb.cyl(mat("metal_paint"), (0, 0, 7.6), 2.6, 0.3, "Z", 20, r2=1.4, col=(0.85, 0.86, 0.85))
	hb.box(mat("hazard"), (0, -2.62, 4.5), (1.6, 0.03, 1.6), (1, 1, 1))
	for k in range(10):
		hb.box(mat("steel"), (2.7, 0, 0.7 + k * 0.7), (0.06, 0.5, 0.04), (0.8, 0.8, 0.8))
	hb.box(mat("concrete"), (0, 0, 0.25), (6.0, 6.0, 0.5), (0.7, 0.7, 0.7))
	return hb.build(name), None

def lab_sign(name):
	hb = HB()
	for x in (-1.1, 1.1):
		hb.box(mat("steel"), (x, 0, 1.0), (0.08, 0.08, 2.0), (0.8, 0.8, 0.8))
	hb.box(mat("hazard"), (0, 0, 1.75), (2.6, 0.05, 1.2), (1, 1, 1))
	text_mesh(hb, "spray", "ОПАСНО!", 0.3, (0, -0.04, 2.0), (0.08, 0.08, 0.08))
	text_mesh(hb, "spray", "БИОЛОГИЧЕСКАЯ", 0.18, (0, -0.04, 1.68), (0.08, 0.08, 0.08))
	text_mesh(hb, "spray", "УГРОЗА", 0.22, (0, -0.04, 1.38), (0.6, 0.06, 0.05))
	return hb.build(name), None

# ---------------- авиация ----------------
def heli_fly(name):
	"""Вертолёт Ми-8-класса в полёте: целый фюзеляж, хвостовая балка с килем и хвостовым винтом, шасси; несущий винт — отдельно (heli_rotor)."""
	hb = HB(keep_winding=True)
	S = dict(L=11.5, W=2.5, top=[(0, 1.2), (0.05, 2.6), (0.15, 3.1), (0.75, 3.15), (0.88, 2.8), (0.96, 1.9), (1.0, 1.2)], clear=0.6, belt=1.9, tumble=0.18, sq=4.0,
		wheel_r=0.0, axles=(), glass=[(10.2, 11.4, "front"), (9.0, 10.8, "side")], lights={"head": (0, 0, 0, 0), "tail": (0, 0, 0, 0), "grille": (0, 0, 0, 0)}, broken=0.0)
	G = (0.30, 0.36, 0.26)
	C.body(hb, S, G, random.Random(6))
	hb.box(mat("paint"), (7.3, 0, 3.45), (4.2, 1.7, 0.75), G)
	hb.box(mat("paint"), (5.0, 0, 3.35), (1.4, 1.3, 0.5), G)
	hb.cyl(mat("frame"), (6.2, 0, 3.95), 0.32, 0.5, "Z", 10, col=(0.2, 0.2, 0.2))
	for sy in (-1, 1):
		for k in range(5):
			hb.cyl(mat("car_glass"), (2.6 + k * 1.15, sy * 1.27, 2.2), 0.22, 0.04, "Y", 10, col=(0.1, 0.12, 0.13))
		hb.cyl(mat("tire"), (8.6, sy * 1.4, 0.35), 0.35, 0.25, "Y", 12, col=(0.05, 0.05, 0.05))
		hb.beam(mat("frame"), (8.6, sy * 1.4, 0.35), (8.0, sy * 1.0, 1.0), 0.08)
		hb.box(mat("paint"), (5.0, sy * 1.6, 1.6), (2.4, 0.6, 0.8), G)                      # топливные баки по бокам
		hb.box(mat("metal_paint"), (3.2, sy * 1.33, 2.6), (0.5, 0.02, 0.5), (0.85, 0.1, 0.08))   # красная звезда-метка
	hb.cyl(mat("paint"), (-3.5, 0, 2.3), 0.45, 8.0, "X", 12, r2=0.25, col=G)
	hb.box(mat("paint"), (-7.4, 0, 3.1), (1.2, 0.15, 1.8), G)
	hb.box(mat("paint"), (-6.6, 0, 2.3), (0.9, 1.8, 0.08), G)
	for k in range(3):
		a = k * 2.09
		hb.box(mat("frame"), (-7.4 + math.cos(a) * 0.6, 0.25, 3.4 + math.sin(a) * 0.6), (1.2, 0.04, 0.16), (0.3, 0.3, 0.3), rot=(0.0, -a, 0.0))
	ob = C.finish(hb, name)
	for v in ob.data.vertices:                                          # центр — под втулкой винта
		v.co.x -= 6.2
	return ob, None

def heli_rotor(name):
	hb = HB()
	hb.cyl(mat("frame"), (0, 0, 0), 0.35, 0.3, "Z", 10, col=(0.2, 0.2, 0.2))
	for k in range(5):
		a = k * 2 * math.pi / 5
		hb.box(mat("frame"), (math.cos(a) * 5.4, math.sin(a) * 5.4, 0.05), (10.6, 0.5, 0.05), (0.25, 0.25, 0.25), rot=(0, 0, a))
	return hb.build(name), None

def plane_jet(name):
	"""Истребитель (Су-27-класса): фюзеляж, остеклённый фонарь, стреловидное крыло, два киля, сопла. Нос в +X."""
	hb = HB(keep_winding=True)
	S = dict(L=21.0, W=2.0, top=[(0, 0.9), (0.04, 1.6), (0.5, 1.9), (0.72, 2.2), (0.8, 2.55), (0.86, 2.2), (0.94, 1.6), (1.0, 1.2)], clear=0.7, belt=1.9, tumble=0.3, sq=3.0,
		wheel_r=0.0, axles=(), glass=[(16.2, 18.4, "side"), (17.8, 18.6, "front")], lights={"head": (0, 0, 0, 0), "tail": (0, 0, 0, 0), "grille": (0, 0, 0, 0)}, broken=0.0)
	G = (0.55, 0.60, 0.66)
	C.body(hb, S, G, random.Random(8))
	hb.poly(mat("paint"), [(4.0, 0, 1.3), (11.5, 0, 1.3), (6.0, 7.2, 1.3), (3.4, 7.2, 1.3)], (0, 0, 0.12), G)          # крыло
	hb.poly(mat("paint"), [(4.0, 0, 1.3), (3.4, -7.2, 1.3), (6.0, -7.2, 1.3), (11.5, 0, 1.3)], (0, 0, 0.12), G)
	hb.poly(mat("paint"), [(0.2, 0, 1.4), (3.4, 0, 1.4), (1.2, 3.4, 1.4), (-0.2, 3.4, 1.4)], (0, 0, 0.08), G)          # стабилизатор
	hb.poly(mat("paint"), [(0.2, 0, 1.4), (-0.2, -3.4, 1.4), (1.2, -3.4, 1.4), (3.4, 0, 1.4)], (0, 0, 0.08), G)
	for sy in (-1.1, 1.1):
		hb.poly(mat("paint"), [(0.4, sy, 2.0), (4.2, sy, 2.0), (2.0, sy, 5.4), (0.9, sy, 5.4)], (0, 0.1, 0), G)        # кили
		hb.cyl(mat("frame"), (-0.1, sy * 0.6, 1.3), 0.55, 0.8, "X", 14, col=(0.2, 0.19, 0.18))                      # сопла
		hb.box(mat("metal_paint"), (2.5, sy * 3.6, 1.38), (0.6, 0.02, 0.6), (0.8, 0.1, 0.08))
	return C.finish(hb, name), None

JOBS = {
	"hero_house": lambda: hero_house("hero_house"),
	"hero_shed": lambda: hero_shed("hero_shed"),
	"bunker_lid": lambda: bunker_lid("bunker_lid"),
	"lounger": lambda: lounger("lounger"),
	"garden_chair": lambda: garden_chair("garden_chair"),
	"garden_table": lambda: garden_table("garden_table"),
	"phone": lambda: phone("phone"),
	"lab_main": lambda: lab_main("lab_main"),
	"lab_wing": lambda: lab_wing("lab_wing"),
	"lab_stack": lambda: lab_stack("lab_stack"),
	"lab_tank": lambda: lab_tank("lab_tank"),
	"lab_sign": lambda: lab_sign("lab_sign"),
	"heli_fly": lambda: heli_fly("heli_fly"),
	"heli_rotor": lambda: heli_rotor("heli_rotor"),
	"plane_jet": lambda: plane_jet("plane_jet"),
}

if __name__ == "__main__":
	out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/houses/story"
	os.makedirs(out, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	objs = []
	only = [x for x in os.environ.get("ONLY", "").split(",") if x]
	i = 0
	for n, fn in JOBS.items():
		if only and n not in only:
			continue
		o, r = fn()
		o.location = ((i % 4) * 28.0, -(i // 4) * 26.0, 0)
		if r is not None:
			r.location = o.location
			objs.append(r)
		objs.append(o)
		print("STORY %-14s %6d тр." % (n, sum(len(p.vertices) - 2 for p in o.data.polygons)), flush=True)
		i += 1
	H.preview(objs, os.path.join(out, "story.png"), pad=6.0)
