"""Пучки растений (outk/*__kN.png + meta_all.json, спецификации pk.json) -> атласы
assets/cover/pieces/<растение>.png + SPRITE_DATA.coverPieces в src/sprites-data.js.
Для каждого пучка: прямоугольник в атласе (sx,sy,sw,sh — px атласа), размер на
экране (w,h), где рисовать относительно корня растения (ax,ay), точка корня самого
пучка (pvx,pvy — вокруг неё он гнётся) и центр пучка (cx,cy), всё в экранных px.
Тень целого растения — outp/<растение>__sh.png (рендер shadowOnly, см. pp-спецификацию)."""
import json, os, re, glob
import numpy as np
from PIL import Image, ImageFilter
PPM=63.2; SS=2; SCREEN=214/360
GAME='/home/user/survival-game'
specs=json.load(open('pk.json')); meta=json.load(open('outk/meta_all.json'))
os.makedirs(GAME+'/assets/cover/pieces',exist_ok=True)
for f in glob.glob(GAME+'/assets/cover/parts/*'): os.remove(f)
if os.path.isdir(GAME+'/assets/cover/parts'): os.rmdir(GAME+'/assets/cover/parts')
k=SCREEN/SS*2
man={}
plants=sorted({n.split('__')[0] for n in specs})
for key in plants:
    items=[]
    for i in range(specs[f'{key}__k0']['pieces']):
        name=f'{key}__k{i}'; sp=specs[name]; fn=f'outk/{name}.png'
        if not os.path.exists(fn) or not meta.get(name): continue
        im=Image.open(fn).convert('RGBA')
        cw,ch,top,ox=sp.get('cw',360),sp.get('ch',720),sp.get('top',0.9),sp.get('ox',0)
        R=sp.get('res',1); D=2*R                  # рендер в R раз крупнее; файл ~2R px на экранный px
        gx=(cw/2-ox*PPM)*SS*R; gy=top*ch*SS*R
        a=np.array(im.getchannel('A')).astype(np.float32)
        bb=im.getchannel('A').point(lambda v:255 if v>6 else 0).getbbox()
        if not bb: continue
        ys,xs=np.nonzero(a>6); wgt=a[ys,xs]
        cx=((xs*wgt).sum()/wgt.sum()-gx)*k/D; cy=((ys*wgt).sum()/wgt.sum()-gy)*k/D
        rx,ry=meta[name]['root']; pvx=(rx*SS-gx)*k/D; pvy=(ry*SS-gy)*k/D
        ax=(gx-bb[0])*k/D; ay=(gy-bb[1])*k/D
        im=im.crop(bb); w=max(1,round(im.width*k)); h=max(1,round(im.height*k))
        im=im.resize((w,h),Image.LANCZOS)
        arr=np.array(im).astype(np.float32)
        arr[:,:,:3]*=np.array([1.22,1.3,1.05]) if key.startswith('grass') else 0.93
        items.append({'img':Image.fromarray(arr.clip(0,255).astype(np.uint8),'RGBA'),'w':w,'h':h,
          'ax':round(ax,1),'ay':round(ay,1),'D':D,'pvx':round(pvx,1),'pvy':round(pvy,1),'cx':round(cx,1),'cy':round(cy,1)})
    # атлас: полки шириной 512, отступ 2 px
    AW=1024; x=y=rowh=0; pos=[]
    for it in items:
        if x+it['w']+2>AW: x=0; y+=rowh+2; rowh=0
        pos.append((x,y)); x+=it['w']+2; rowh=max(rowh,it['h'])
    atlas=Image.new('RGBA',(AW,y+rowh+2),(0,0,0,0))
    pcs=[]
    for it,(px,py) in zip(items,pos):
        atlas.paste(it['img'],(px,py))
        pcs.append({'sx':px,'sy':py,'sw':it['w'],'sh':it['h'],'w':round(it['w']/it['D'],1),'h':round(it['h']/it['D'],1),
          'ax':it['ax'],'ay':it['ay'],'pvx':it['pvx'],'pvy':it['pvy'],'cx':it['cx'],'cy':it['cy']})
    out=f'assets/cover/pieces/{key}.png'; atlas.save(GAME+'/'+out,optimize=True)
    # тень целого растения
    shf=f'outp/{key}__sh.png'; sh=None
    if os.path.exists(shf):
        im=Image.open(shf).convert('RGBA'); sp=specs[f'{key}__k0']
        cw,ch,top,ox=sp.get('cw',360),sp.get('ch',720),sp.get('top',0.9),sp.get('ox',0)
        gx=(cw/2-ox*PPM)*SS; gy=top*ch*SS
        bb=im.getchannel('A').point(lambda v:255 if v>6 else 0).getbbox()
        if bb:
            im=im.crop(bb); w=max(1,round(im.width*k)); h=max(1,round(im.height*k))
            al=im.getchannel('A').resize((w,h),Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.5))
            im=Image.new('RGBA',(w,h),(0,0,0,0)); im.putalpha(al)
            sf=f'assets/cover/pieces/{key}_sh.png'; im.save(GAME+'/'+sf,optimize=True)
            sh={'file':sf,'w':round(w/2,1),'h':round(h/2,1),'ax':round((gx-bb[0])*k/2,1),'ay':round((gy-bb[1])*k/2,1)}
    man[key]={'file':out,'pieces':pcs,'shadow':sh}
p=GAME+'/src/sprites-data.js'; s=open(p).read()
s=re.sub(r'\nSPRITE_DATA\.coverParts = .*','',s,flags=re.S)
s=re.sub(r'\nSPRITE_DATA\.coverPieces = .*','',s,flags=re.S)
s+="\nSPRITE_DATA.coverPieces = "+json.dumps(man,ensure_ascii=False)+";\n"
open(p,'w').write(s); print(len(man),'plants',sum(len(m['pieces']) for m in man.values()),'pieces')
