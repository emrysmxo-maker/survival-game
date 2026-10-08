# Картинки результата → JPG не больше 1 МБ (коннекторы GitHub у ИИ не отдают файлы > 1 МБ). python -I shrink_out.py <папка>
import os, sys
from PIL import Image
LIM = 950_000
for root, _, files in os.walk(sys.argv[1]):
	for f in files:
		p = os.path.join(root, f)
		if not f.lower().endswith((".png", ".jpg", ".jpeg")) or os.path.getsize(p) <= LIM:
			continue
		im = Image.open(p).convert("RGB")
		dst = os.path.splitext(p)[0] + ".jpg"
		q, k = 85, 1.0
		while True:
			w, h = int(im.width * k), int(im.height * k)
			(im if k == 1.0 else im.resize((w, h), Image.LANCZOS)).save(dst, quality=q)
			if os.path.getsize(dst) <= LIM or k < 0.3:
				break
			if q > 70: q -= 7
			else: k *= 0.85
		if dst != p:
			os.remove(p)
		print("jpg", os.path.relpath(dst, sys.argv[1]), os.path.getsize(dst) // 1024, "КБ")
