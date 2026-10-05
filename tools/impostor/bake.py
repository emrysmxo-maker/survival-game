# Запекание импосторов: python3 bake.py specs.json outdir
# Для каждого объекта: <name>_albedo.png (RGBA), <name>_ndt.png (нормаль xy, глубина, AO), и общий meta.json.
import sys, json, base64, asyncio, io, os, time
import numpy as np
from PIL import Image
from playwright.async_api import async_playwright

def dec(url):
    return Image.open(io.BytesIO(base64.b64decode(url.split(',')[1])))

def down(a, ss):
    h, w = a.shape[0] // ss, a.shape[1] // ss
    return a[:h*ss, :w*ss].reshape(h, ss, w, ss, -1).mean(axis=(1, 3))

def dilate(rgb, mask, n=12):
    # заливаем прозрачные пиксели цветом соседей (чтобы в мип-уровнях не было тёмной каймы)
    rgb = rgb.copy(); m = mask.copy()
    for _ in range(n):
        acc = np.zeros_like(rgb); cnt = np.zeros(m.shape)
        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
            sh = np.roll(np.roll(rgb * m[..., None], dy, 0), dx, 1); sm = np.roll(np.roll(m, dy, 0), dx, 1)
            acc += sh; cnt += sm
        new = (cnt > 0) & (m == 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        m = np.where(new, 1.0, m)
    return rgb

def save(name, out, odir):
    meta = out['meta']; ss = meta['ss']
    alb = np.asarray(dec(out['albedo']).convert('RGBA')).astype(np.float32) / 255
    ndt = np.asarray(dec(out['ndt']).convert('RGBA')).astype(np.float32) / 255
    ao = np.asarray(dec(out['ao']).convert('L')).astype(np.float32)[..., None] / 255
    a = alb[..., 3:4]
    # усреднение с учётом покрытия (без краёв фона)
    A = down(a, ss)
    def avg(x):
        return down(x * a, ss) / np.maximum(A, 1e-4)
    rgb = avg(alb[..., :3]); nd = avg(ndt[..., :3]); o = avg(ao)
    m = (A[..., 0] > 0.02).astype(np.float32)
    rgb = dilate(rgb, m); nd = dilate(nd, m); o = dilate(o, m)
    Image.fromarray((np.concatenate([rgb, A], -1).clip(0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(f'{odir}/{name}_albedo.png', optimize=True)
    Image.fromarray((np.concatenate([nd, o], -1).clip(0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(f'{odir}/{name}_ndt.png', optimize=True)
    meta = dict(meta); meta['w'] = rgb.shape[1]; meta['h'] = rgb.shape[0]
    return meta

async def run(specs, odir):
    os.makedirs(odir, exist_ok=True)
    mp = f'{odir}/meta.json'
    allm = json.load(open(mp)) if os.path.exists(mp) else {}
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/opt/pw-browsers/chromium', args=['--use-gl=swiftshader', '--enable-webgl', '--ignore-gpu-blocklist', '--js-flags=--max-old-space-size=12000'])
        page = await b.new_page(viewport={'width': 800, 'height': 600})
        page.on('pageerror', lambda e: print('ERR', e))
        page.on('console', lambda m: print('C:', m.text[:300]) if 'GL Driver' not in m.text and 'favicon' not in m.text and 'GPU stall' not in m.text else None)
        await page.goto('http://localhost:8791/bake.html')
        await page.wait_for_function('window.ready===true', timeout=60000)
        for name, spec in specs.items():
            if name in allm and not os.environ.get('FORCE'):
                print('skip', name); continue
            t = time.time()
            out = await page.evaluate("s=>window.bake(s)", spec)
            allm[name] = save(name, out, odir)
            allm[name]['spec'] = spec
            json.dump(allm, open(mp, 'w'), indent=1)
            print('ok', name, allm[name]['w'], 'x', allm[name]['h'], '%.0fs' % (time.time() - t), flush=True)
        await b.close()

if __name__ == '__main__':
    asyncio.run(run(json.load(open(sys.argv[1])), sys.argv[2]))
