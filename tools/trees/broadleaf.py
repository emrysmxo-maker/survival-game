# Лиственные породы для treegen.py: осина, дуб, ольха, ива, яблоня.
# Подключается внутрь treegen.py (exec) — использует его функции и глобальные переменные.

def leaf_atlas(shape, greens, pet=0.25, teeth=(15, 0.05, 43, 0.02), veins=9.0, S=256, pet_col=(0.45, 0.40, 0.17)):
	"""4 листа одной породы 2x2. shape(xb) -> полуширина (доля длины пластинки)."""
	out = np.zeros((S * 2, S * 2, 4))
	vv, uu = np.meshgrid((np.arange(S) + 0.5) / S, (np.arange(S) + 0.5) / S, indexing="ij")
	px = (1 + pet) / S
	for c in range(4):
		ci, cj = c % 2, c // 2
		k = 0.92 + 0.08 * c / 3
		x = vv * (1 + pet) - pet
		y = (uu - 0.5) + 0.025 * (c - 1.5) * np.clip(x, 0, 1) ** 2
		xb = np.clip(x, 0, 1)
		wv = shape(xb) * k
		t = (((x * (teeth[0] + c)) % 1.0) ** 2) * teeth[1] + (((x * (teeth[2] + 2 * c)) % 1.0) ** 2) * teeth[3]
		wt = wv * (1 - t * (x > 0.06))
		a_blade = np.clip((wt - np.abs(y)) / px + 0.5, 0, 1) * ((x >= 0) & (x <= 1))
		a_pet = np.clip((0.013 - np.abs(y)) / px + 0.5, 0, 1) * ((x < 0.03) & (x > -pet * 0.92))
		a = np.maximum(a_blade, a_pet)
		g = np.array(greens[c % len(greens)])
		col = np.ones((S, S, 3)) * g
		mid = np.exp(-np.abs(y) / 0.012)
		vein = np.exp(-(((x - np.abs(y) * 1.15) * veins + 0.5) % 1.0 - 0.5) ** 2 / 0.003) * (np.abs(y) < wt * 0.9)
		edge = np.clip(1 - (wt - np.abs(y)) / (np.maximum(wt, 1e-3) * 0.25), 0, 1)
		col += (mid * 0.10 + vein * 0.04)[..., None] * np.array([0.9, 1.0, 0.5])
		col *= (1 - edge * 0.18)[..., None]
		col = np.where((a_pet > a_blade)[..., None], np.array(pet_col), col)
		col = np.where((a > 0.01)[..., None], col, g)
		out[cj * S:(cj + 1) * S, ci * S:(ci + 1) * S, :3] = col
		out[cj * S:(cj + 1) * S, ci * S:(ci + 1) * S, 3] = a
	return out

def _oak_shape(xb):
	base = (xb ** 0.6) * ((1 - xb) ** 0.3) / 0.564
	return 0.40 * base * (0.52 + 0.48 * np.abs(np.cos(np.pi * xb * 4.5)))

BROAD_P = {
	"aspen": dict(H0=20.0, r0=0.17, cs=0.4, n1=48, p0=62, p1=30, L0=0.8, L1=3.4, env=lambda u: math.sin(math.pi * min(1.0, u * 0.9 + 0.1)) ** 0.8,
		up=0.55, down=0.35, bw=0.2, l2=False, ss=0.22, sz=(0.6, 1.0), roll=(20, 100), tw=0.012, lean=0.01, base=True,
		leaf=dict(shape=lambda xb: 0.47 * np.sqrt(np.clip(1 - (2 * xb - 1) ** 2, 0, 1)) * (1 - 0.12 * xb) + 0.02, pet=0.55, teeth=(11, 0.045, 0, 0), veins=7.0,
			greens=[(0.30, 0.43, 0.18), (0.34, 0.46, 0.20), (0.28, 0.40, 0.16), (0.36, 0.45, 0.17)]), ls=0.06, lsp=0.03),
	"oak": dict(H0=18.0, r0=0.42, cs=0.22, n1=15, p0=70, p1=48, L0=4.5, L1=4.5, env=lambda u: (1 - u) ** 0.5,
		up=0.75, down=0.35, bw=0.6, l2=True, l2s=0.95, ss=0.3, sz=(1.15, 1.6), roll=(40, 110), tw=0.03, lean=0.04, base=False, topk=0.62,
		leaf=dict(shape=_oak_shape, pet=0.1, teeth=(1, 0, 0, 0), veins=5.0,
			greens=[(0.20, 0.33, 0.09), (0.23, 0.36, 0.10), (0.18, 0.30, 0.08), (0.25, 0.35, 0.11)]), ls=0.09, lsp=0.035),
	"alder": dict(H0=16.0, r0=0.15, cs=0.3, n1=44, p0=68, p1=38, L0=0.7, L1=2.8, env=lambda u: (1 - u) ** 0.7 * 0.9 + 0.1,
		up=0.4, down=0.3, bw=0.2, l2=False, ss=0.22, sz=(0.6, 0.95), roll=(30, 100), tw=0.012, lean=0.015, base=False,
		leaf=dict(shape=lambda xb: 0.47 * np.clip(np.sin(np.pi * np.clip(xb * 0.9 + 0.08, 0, 1)), 0, 1) ** 0.55 * (0.7 + 0.3 * xb), pet=0.25, teeth=(13, 0.04, 39, 0.02), veins=7.0,
			greens=[(0.17, 0.30, 0.08), (0.19, 0.32, 0.09), (0.16, 0.28, 0.07), (0.20, 0.31, 0.10)]), ls=0.07, lsp=0.032),
	"willow": dict(H0=12.0, r0=0.2, cs=0.25, n1=26, p0=55, p1=25, L0=1.5, L1=4.0, env=lambda u: math.sin(math.pi * min(1.0, u * 0.8 + 0.2)),
		up=0.6, down=0.9, bw=0.3, l2=True, l2s=0.6, ss=0.28, sz=(0.7, 1.1), roll=(0, 70), tw=0.03, lean=0.25, base=False, stems=3,
		leaf=dict(shape=lambda xb: 0.13 * np.sin(np.pi * xb) ** 0.75, pet=0.08, teeth=(40, 0.03, 0, 0), veins=14.0,
			greens=[(0.38, 0.47, 0.27), (0.35, 0.44, 0.25), (0.42, 0.50, 0.30), (0.33, 0.42, 0.22)]), ls=0.10, lsp=0.022),
	"apple": dict(H0=5.5, r0=0.14, cs=0.22, n1=10, p0=58, p1=35, L0=2.0, L1=1.6, env=lambda u: 1.0 - 0.3 * u,
		up=0.6, down=0.7, bw=0.6, l2=True, l2s=0.3, ss=0.18, sz=(0.6, 0.9), roll=(30, 110), tw=0.03, lean=0.06, base=False,
		leaf=dict(shape=lambda xb: 0.34 * np.sin(np.pi * xb ** 0.85) ** 0.85, pet=0.25, teeth=(30, 0.03, 0, 0), veins=8.0,
			greens=[(0.27, 0.40, 0.13), (0.30, 0.43, 0.15), (0.25, 0.38, 0.12), (0.31, 0.41, 0.14)]), ls=0.065, lsp=0.03, fruit=True),
	# черёмуха: многоствольная, 6–9 м, у воды и на опушках; лист эллиптический, заострённый, мелкозубчатый, тёмный
	"cherry": dict(H0=7.5, r0=0.11, cs=0.3, n1=16, p0=50, p1=32, L0=1.6, L1=2.2, env=lambda u: math.sin(math.pi * min(1.0, u * 0.85 + 0.15)) ** 0.7,
		up=0.55, down=0.55, bw=0.35, l2=True, l2s=0.5, ss=0.2, sz=(0.6, 0.95), roll=(30, 110), tw=0.03, lean=0.14, base=False, stems=3,
		leaf=dict(shape=lambda xb: 0.30 * np.sin(np.pi * xb ** 0.8) ** 0.9 * (1.0 - 0.25 * xb ** 3), pet=0.2, teeth=(36, 0.018, 0, 0), veins=9.0,
			greens=[(0.15, 0.27, 0.08), (0.17, 0.29, 0.09), (0.14, 0.25, 0.07), (0.18, 0.28, 0.10)]), ls=0.07, lsp=0.03),
}

def trunk_az(H, r0, seg, lean, az, wander, flare=0.45):
	tp, tr = [], []
	d = Vector((lean * math.cos(az), lean * math.sin(az), 1)).normalized()
	p = Vector((0, 0, -0.15))
	for k in range(seg + 1):
		t = k / seg
		r = r0 * (1 - t) ** 0.85 + 0.008
		if t < 0.05:
			r *= 1 + (0.05 - t) / 0.05 * flare
		tp.append(p.copy()); tr.append(r)
		d = (d + rand_dir() * wander).normalized()
		p = p + d * (H / seg)
	return tp, tr

def broad_frame(sp, H):
	P = BROAD_P[sp]
	k = H / P["H0"]
	stems = P.get("stems", 1)
	trunks, L1s, sprays, stubs = [], [], [], []
	ks = min(1.0, 0.45 + k * 0.55)
	for s in range(stems):
		Hs = H * (1.0 if s == 0 else R(0.7, 0.92)) * P.get("topk", 1.0)
		az0 = R(0, 6.28) if stems > 1 else 0.6
		tp, tr = trunk_az(Hs, P["r0"] * max(k, 0.25) * (1.0 if stems == 1 else 0.7), max(8, int(16 * min(1, k * 1.5))), P["lean"] * (1 if s == 0 else 2.5), az0 + s * 2.1, P["tw"])
		trunks.append((tp, tr))
		n1 = max(4, int(P["n1"] * min(1.0, k ** 0.5) / stems))
		az = R(0, 6.28)
		for i in range(n1):
			u = i / max(1, n1 - 1)
			t = P["cs"] + (0.97 - P["cs"]) * u
			q, dq, rq = sample(tp, tr, t)
			az += 2.40 + R(-0.4, 0.4)
			L1 = max(0.4 * k, (P["L0"] + P["L1"] * P["env"](u)) * R(0.8, 1.15) * k)
			pitch = math.radians(P["p0"] + (P["p1"] - P["p0"]) * u + R(-10, 10))
			d0 = Vector((math.sin(pitch) * math.cos(az), math.sin(pitch) * math.sin(az), math.cos(pitch)))
			r0 = min(rq * 0.72, (0.012 + 0.05 * L1 / 5.0) * max(k, 0.3))
			up, dn = P["up"], P["down"]
			p1, r1 = grow(q - d0 * rq * 0.5, d0, L1, r0, 0.006, max(3, int(L1 / 0.7)),
				lambda t, up=up, dn=dn: UP * (up * (1 - t) - dn * t * t), P["bw"])
			L1s.append((p1, r1))
			limbs = [(p1, r1, L1)]
			if P["l2"]:
				n2 = max(1, int(L1 / P["l2s"]))
				for j in range(n2):
					tb = 0.2 + 0.75 * j / n2 + R(-0.04, 0.04)
					q2, d2, rr2 = sample(p1, r1, tb)
					sd = side_dir(d2, 1 if j % 2 else -1, R(-0.3, 0.8))
					dd = (d2 * 0.55 + sd * 0.8).normalized()
					L2 = max(0.4, L1 * (0.55 - 0.3 * tb) * R(0.75, 1.2))
					p2, r2 = grow(q2, dd, L2, min(rr2 * 0.7, 0.012 + 0.02 * L2), 0.004, max(2, int(L2 / 0.6)),
						lambda t, up=up, dn=dn: UP * (up * 0.6 * (1 - t) - dn * t * t), P["bw"] * 1.2)
					L1s.append((p2, r2))
					limbs.append((p2, r2, L2))
			for (pl, rl, Ll) in limbs:
				nsp = max(1, int(Ll / P["ss"]))
				for j in range(nsp):
					tb = 0.25 + 0.75 * j / nsp + R(-0.03, 0.03)
					q2, d2, _ = sample(pl, rl, tb)
					sd = side_dir(d2, 1 if j % 2 else -1, R(-0.4, 0.6))
					dd = (d2 * 0.6 + sd * 0.7 + UP * 0.15).normalized()
					if sp == "willow":
						dd = (dd + Vector((0, 0, -0.9))).normalized()
					sprays.append((q2, dd, math.radians(R(*P["roll"])), R(*P["sz"]) * ks))
				q3, d3, _ = sample(pl, rl, 1.0)
				sprays.append((q3 - d3 * 0.1, (d3 + rand_dir() * 0.4).normalized(), math.radians(R(*P["roll"])), R(*P["sz"]) * ks))
		for _ in range(int(5 * min(1, k))):
			q, dq, rq = sample(tp, tr, R(0.1, P["cs"]))
			a = R(0, 6.28)
			dd = Vector((math.cos(a), math.sin(a), R(-0.2, 0.4))).normalized()
			stubs.append(grow(q, dd, R(0.15, 0.5) * k, 0.015 * k + 0.004, 0.004, 2, lambda t: Vector(), 0.3))
	return trunks, L1s, sprays, stubs

def twig_broad(sp):
	"""Ветка лиственной породы в горизонтальной плоскости (листья смотрят вверх) -> плоскость карточки."""
	P = BROAD_P[sp]
	M = Mesh()
	seed(zlib.crc32(sp.encode()))
	L = 0.9
	p0, r0 = grow(Vector((0, 0, 0)), Vector((1, 0, 0)), L, 0.007, 0.002, 8, lambda t: Vector(), 0.25)
	shoots = [(p0, r0)]
	nb = int(L / 0.09)
	for j in range(nb):
		t = 0.1 + 0.85 * j / nb
		q, d, rr = sample(p0, r0, t)
		sd = side_dir(d, 1 if j % 2 else -1, R(-0.15, 0.15))
		dd = (d * 0.5 + sd * 0.85).normalized()
		ps, rs = grow(q, dd, R(0.12, 0.32) * (1.1 - 0.6 * t), rr * 0.7, 0.0015, 4, lambda t: Vector(), 0.35)
		shoots.append((ps, rs))
	for (ps, rs) in shoots:
		twig_tube(M, ps, rs, 4, (0.17, 0.13, 0.10))
		Ls = sum((ps[i + 1] - ps[i]).length for i in range(len(ps) - 1))
		n = max(2, int(Ls / P["lsp"]))
		for i in range(n):
			q, d, _ = sample(ps, rs, 0.1 + 0.9 * i / n)
			sd = side_dir(d, 1 if i % 2 else -1, R(-0.3, 0.3))
			ld = (d * 0.45 + sd * 0.85 + rand_dir() * 0.25).normalized()
			ld = Vector((ld.x, ld.y, ld.z * 0.3)).normalized()
			nn = (UP + rand_dir() * 0.45)
			nn = (nn - ld * nn.dot(ld)).normalized()
			t = 1.0 if rnd.random() < 0.03 else R(0.82, 1.0)
			leaf_quad(M, q, ld, nn, P["ls"] * R(0.8, 1.15), rnd.randrange(4), (t, t, t, 1.0) if t < 1 else (1.5, 1.2, 0.3, 1.0))
	if P.get("fruit"):                                                 # яблоки-дички
		for _ in range(7):
			ps, rs = shoots[rnd.randrange(1, len(shoots))]
			q, d, _ = sample(ps, rs, R(0.4, 1.0))
			c = (0.55, 0.12, 0.05) if rnd.random() < 0.6 else (0.62, 0.55, 0.12)
			rr = R(0.025, 0.035)
			for f in range(8):
				a0, a1 = f / 8 * 6.283, (f + 1) / 8 * 6.283
				b = len(M.v)
				M.v += [tuple(q + Vector((0, 0, rr * 0.2))), tuple(q + Vector((math.cos(a0) * rr, math.sin(a0) * rr, 0))), tuple(q + Vector((math.cos(a1) * rr, math.sin(a1) * rr, 0)))]
				M.f.append((b, b + 1, b + 2)); M.fm.append(2); M.uv += [(0, 0), (1, 0), (0, 1)]
				M.col += [c + (1,)] * 3
	to_card_plane(M, 0.35)
	M.atlas = sp
	return M

def bark_aspen():
	h, w = BH, BW
	low = fnoise(h, w, 1.8)
	col = np.ones((h, w, 3)) * np.array([0.60, 0.62, 0.52]) + low[..., None] * 0.04
	dark = np.zeros((h, w))
	for _ in range(90):                                                # ромбики-чечевички
		stamp(dark, R(0.6, 1.0), R(0, w), R(0, h), R(10, 28), R(3, 7), 0.0)
	for _ in range(400):
		stamp(dark, R(0.3, 0.6), R(0, w), R(0, h), R(4, 14), R(0.5, 1.2), 0.2)
	col = col * (1 - dark[..., None]) + np.array([0.16, 0.15, 0.13]) * dark[..., None]
	return col, 0.6 + low * 0.03 - dark * 0.3

def _fissured(c_ridge, c_deep, ay=4.0, width=0.3):
	h, w = BH, BW
	n = fnoise(h, w, 1.4, ay=ay)
	n2 = fnoise(h, w, 1.7)
	crack = np.clip(1 - np.abs(n) / width, 0, 1) ** 1.2
	plate = np.clip(0.5 + n2 * 0.3, 0, 1)
	pc = np.array(c_ridge) * (0.85 + 0.3 * plate[..., None])
	col = pc * (1 - crack[..., None]) + np.array(c_deep) * crack[..., None]
	return col, 0.75 - crack * 0.6 + n2 * 0.05

def bark_oak():
	return _fissured((0.33, 0.30, 0.26), (0.06, 0.05, 0.045), 5.0, 0.38)

def bark_alder():
	return _fissured((0.25, 0.23, 0.21), (0.07, 0.06, 0.05), 2.5, 0.2)

def bark_willow():
	return _fissured((0.42, 0.40, 0.35), (0.10, 0.09, 0.08), 6.0, 0.42)

def bark_aspen_base():
	return _fissured((0.34, 0.33, 0.30), (0.06, 0.055, 0.05), 4.0, 0.3)

def bark_cherry():
	"""Черёмуха: гладкая тёмно-серая кора с поперечными светлыми чечевичками."""
	h, w = BH, BW
	n2 = fnoise(h, w, 1.1)
	col = np.ones((h, w, 3)) * np.array([0.21, 0.19, 0.18]) + n2[..., None] * 0.03
	ys, xs = np.mgrid[0:h, 0:w]
	rng = np.random.default_rng(7)
	lent = np.zeros((h, w))
	for _ in range(220):
		cy, cx, L = rng.integers(0, h), rng.integers(0, w), rng.integers(6, 18)
		lent[max(0, cy - 1):cy + 1, cx:min(w, cx + L)] = 1.0
	col = col * (1 - lent[..., None] * 0.5) + np.array([0.48, 0.44, 0.38]) * lent[..., None] * 0.5
	return col, 0.45 + n2 * 0.04 + lent * 0.2

def bark_apple():
	h, w = BH, BW
	n = fnoise(h, w, 1.5, ax=1.5)
	n2 = fnoise(h, w, 1.1)
	flake = np.clip(1 - np.abs(n) / 0.2, 0, 1)
	col = np.ones((h, w, 3)) * np.array([0.36, 0.32, 0.27]) + n2[..., None] * 0.04
	col = col * (1 - flake[..., None] * 0.6) + np.array([0.45, 0.33, 0.22]) * (n2[..., None] > 1.2) * 0.3
	return col, 0.6 - flake * 0.4 + n2 * 0.05
