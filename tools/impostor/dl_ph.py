# Скачивание моделей Poly Haven (CC0) в формате glTF нужного разрешения: python3 dl_ph.py 2k id1 id2 ...
import sys, json, os, urllib.request
opener = urllib.request.build_opener(); opener.addheaders = [('User-Agent', 'survival-game-asset-fetch/1.0')]; urllib.request.install_opener(opener)
res = sys.argv[1]
for aid in sys.argv[2:]:
    info = json.load(urllib.request.urlopen(f'https://api.polyhaven.com/files/{aid}'))
    g = info['gltf'][res]['gltf']
    d = f'plants/{aid}'; os.makedirs(d, exist_ok=True)
    urllib.request.urlretrieve(g['url'], f'{d}/{aid}.gltf')
    for path, f in g.get('include', {}).items():
        p = f'{d}/{path}'; os.makedirs(os.path.dirname(p), exist_ok=True)
        if not os.path.exists(p):
            urllib.request.urlretrieve(f['url'], p)
    print('ok', aid, flush=True)
