# Скачать фото-текстуры CC0 (Poly Haven, 1K jpg: цвет + нормали) для домов: python3 tools/houses/get_tex.py <папка>
import json, os, sys, urllib.request
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/houses/tex"
IDS = ["wood_trunk_wall", "blue_painted_planks", "green_rough_planks", "weathered_plank_siding", "wood_peeling_paint_weathered",
	"brick_wall_02", "painted_worn_brick", "yellow_plaster", "beige_wall_001", "white_plaster_rough_01", "worn_mossy_plasterwall",
	"concrete_block_wall", "corrugated_iron", "rusty_corrugated_iron", "box_profile_metal_sheet", "roof_slates_02",
	"old_wooden_floor_01", "old_linoleum_flooring_01", "decrepit_wallpaper", "peeling_painted_wall", "concrete_wall_006", "rough_pine_door"]
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (survival-game texture fetch)"}

def get(url):
	return urllib.request.urlopen(urllib.request.Request(url, headers=UA))

for i in IDS:
	files = json.load(get("https://api.polyhaven.com/files/" + i))
	for key, suf in (("Diffuse", "diff"), ("nor_gl", "nor")):
		dst = os.path.join(OUT, "%s_%s.jpg" % (i, suf))
		if os.path.exists(dst):
			continue
		url = files[key]["1k"]["jpg"]["url"]
		open(dst, "wb").write(get(url).read())
	print("ok", i, flush=True)
