# Ужать фото-текстуры домов для игры: цвет 1024 q78, нормали 512 q85. python -I shrink_tex.py <tex> <tex_game>
import os, sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for f in sorted(os.listdir(src)):
	if not f.endswith(".jpg") or os.path.exists(os.path.join(dst, f)):
		continue
	nor = f.endswith("_nor.jpg")
	s = 512 if nor else 1024
	im = Image.open(os.path.join(src, f)).convert("RGB")
	im.resize((s, s), Image.LANCZOS).save(os.path.join(dst, f), quality=85 if nor else 78)
