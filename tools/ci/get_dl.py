# Небо (HDRI) и земля Poly Haven (CC0) для рендеров-превью: python3 get_dl.py <папка>
import json, os, sys, urllib.request
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (survival-game texture fetch)"}
get = lambda u: urllib.request.urlopen(urllib.request.Request(u, headers=UA))
NEED = [("kloofendal_48d_partly_cloudy_puresky", [("hdri", "hdr", "kloofendal_48d_partly_cloudy_puresky_2k.hdr")]),
	("aerial_grass_rock", [("Diffuse", "jpg", "aerial_grass_rock_diff_2k.jpg"), ("nor_gl", "jpg", "aerial_grass_rock_nor_gl_2k.jpg"), ("Rough", "jpg", "aerial_grass_rock_rough_2k.jpg")]),
	("leafy_grass", [("Diffuse", "jpg", "leafy_grass_diff_2k.jpg"), ("nor_gl", "jpg", "leafy_grass_nor_gl_2k.jpg"), ("Rough", "jpg", "leafy_grass_rough_2k.jpg")])]
for aid, items in NEED:
	files = None
	for key, fmt, name in items:
		dst = os.path.join(OUT, name)
		if os.path.exists(dst):
			continue
		files = files or json.load(get("https://api.polyhaven.com/files/" + aid))
		open(dst, "wb").write(get(files[key]["2k"][fmt]["url"]).read())
		print("ok", name, flush=True)
