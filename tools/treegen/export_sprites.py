"""Рендеры (out/*.png) -> обрезанные спрайты в assets/ + манифест src/sprites-data.js.
Точка земли в холсте: x = cw/2 - ox*PPM, y = top*ch (px холста), рендер x2 (SS)."""
import json, os
import numpy as np
from PIL import Image, ImageFilter
PPM=63.2; SS=2; SCREEN=214/360      # px экрана на px холста (как деревья)
GAME='/home/user/survival-game'
specs={}
for f in ['p3.json','p4.json','p5.json','sh.json']: specs.update(json.load(open(f)))
man={'cover':{}, 'treeShadow':{}, 'rock':{}}
def grade(im,k):
    a=np.array(im).astype(np.float32)
    rgb=a[:,:,:3]
    if k.startswith('rock'):
        g=rgb.mean(2,keepdims=True); rgb=(g+(rgb-g)*0.35)*np.array([0.93,0.97,0.9])*0.95
    elif k.startswith('grass'):
        rgb=rgb*np.array([1.22,1.3,1.05])       # осветляем: тёмные пучки выглядели плоскими пятнами
    else:
        rgb=rgb*0.93
    a[:,:,:3]=rgb
    return Image.fromarray(a.clip(0,255).astype(np.uint8),'RGBA')
os.makedirs(GAME+'/assets/cover',exist_ok=True); os.makedirs(GAME+'/assets/shadows',exist_ok=True)
for name,sp in specs.items():
    fn=f'out/{name}.png'
    if not os.path.exists(fn): continue
    im=Image.open(fn).convert('RGBA')
    cw,ch,top,ox=sp.get('cw',360),sp.get('ch',720),sp.get('top',0.9),sp.get('ox',0)
    R=sp.get('res',1)                       # рендер в R раз крупнее (render.html spec.res)
    gx=(cw/2-ox*PPM)*SS*R; gy=top*ch*SS*R
    bb=im.getchannel('A').point(lambda v:255 if v>6 else 0).getbbox()
    im=im.crop(bb); ax=gx-bb[0]; ay=gy-bb[1]
    shadow=name.startswith('sh_')
    k=SCREEN/SS*(1 if shadow else 2)          # во сколько раз уменьшить
    w=max(1,round(im.width*k)); h=max(1,round(im.height*k))
    im=im.resize((w,h),Image.LANCZOS)
    if shadow:
        a=im.getchannel('A').filter(ImageFilter.GaussianBlur(1.2))
        im=Image.new('RGBA',im.size,(0,0,0,0)); im.putalpha(a)
        key=name[3:]; out=f'assets/shadows/{key}.png'
        man['treeShadow'][key]={'file':out,'w':w,'h':h,'ax':round(ax*k,1),'ay':round(ay*k,1)}
    else:
        im=grade(im,name)
        D=2*R                               # во сколько раз файл крупнее экранных px (2R ≈ 3.4)
        if name.startswith('rock_'):
            key=name[5:]; out=f'assets/rocks/{key}.png'; group='rock'
        else:
            key=name; out=f'assets/cover/{key}.png'; group='cover'
        man[group][key]={'file':out,'w':round(w/D,1),'h':round(h/D,1),'ax':round(ax*k/D,1),'ay':round(ay*k/D,1)}
    im.save(GAME+'/'+out, optimize=True)
import re
prev=open(GAME+'/src/sprites-data.js').read() if os.path.exists(GAME+'/src/sprites-data.js') else ''
keep=re.search(r'\nSPRITE_DATA\.coverPieces = .*',prev,flags=re.S)   # пучки растений пишет export_pieces.py — не терять
open(GAME+'/src/sprites-data.js','w').write(
 "// Сгенерировано tools/treegen/export_sprites.py — размеры (w,h) и точка земли (ax,ay)\n"
 "// в экранных px при масштабе 1. Картинки подлеска и камней — x2 (чёткость на телефоне).\n"
 "const SPRITE_DATA = "+json.dumps(man,ensure_ascii=False,indent=1)+";\n")
print({g:len(v) for g,v in man.items()})
if keep: open(GAME+'/src/sprites-data.js','a').write(keep.group(0))
