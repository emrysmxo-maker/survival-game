"""Части растений (outp/*__pK.png, *__sh.png, спецификации pp.json) -> assets/cover/parts/
+ SPRITE_DATA.coverParts в src/sprites-data.js (дописывает к манифесту export_sprites.py).
Все части одного растения рендерятся одной камерой: точка корня у них общая.
cx, cy — центр тяжести части относительно корня (экранные px): по нему игра
решает, куда отклонять часть и рисовать её до или после бойца."""
import json, os, re
import numpy as np
from PIL import Image, ImageFilter
PPM=63.2; SS=2; SCREEN=214/360
GAME='/home/user/survival-game'
specs=json.load(open('pp.json'))
os.makedirs(GAME+'/assets/cover/parts',exist_ok=True)
man={}
for name,sp in specs.items():
    fn=f'outp/{name}.png'
    if not os.path.exists(fn): continue
    key,part=name.split('__')
    im=Image.open(fn).convert('RGBA')
    cw,ch,top,ox=sp.get('cw',360),sp.get('ch',720),sp.get('top',0.9),sp.get('ox',0)
    gx=(cw/2-ox*PPM)*SS; gy=top*ch*SS
    a=np.array(im.getchannel('A')).astype(np.float32)
    bb=im.getchannel('A').point(lambda v:255 if v>6 else 0).getbbox()
    if not bb: continue
    k=SCREEN/SS*2
    ent=man.setdefault(key,{'parts':[],'shadow':None})
    if part=='sh':
        im=im.crop(bb); ax=gx-bb[0]; ay=gy-bb[1]
        w=max(1,round(im.width*k)); h=max(1,round(im.height*k))
        al=im.getchannel('A').resize((w,h),Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.5))
        im=Image.new('RGBA',(w,h),(0,0,0,0)); im.putalpha(al)
        out=f'assets/cover/parts/{key}_sh.png'
        ent['shadow']={'file':out,'w':round(w/2,1),'h':round(h/2,1),'ax':round(ax*k/2,1),'ay':round(ay*k/2,1)}
    else:
        ys,xs=np.nonzero(a>6); wgt=a[ys,xs]
        cx=((xs*wgt).sum()/wgt.sum()-gx)*k/2; cy=((ys*wgt).sum()/wgt.sum()-gy)*k/2
        im=im.crop(bb); ax=gx-bb[0]; ay=gy-bb[1]
        w=max(1,round(im.width*k)); h=max(1,round(im.height*k))
        im=im.resize((w,h),Image.LANCZOS)
        arr=np.array(im).astype(np.float32)
        mul=np.array([1.22,1.3,1.05]) if key.startswith('grass') else 0.93
        arr[:,:,:3]*=mul; im=Image.fromarray(arr.clip(0,255).astype(np.uint8),'RGBA')
        i=int(part[1:]); out=f'assets/cover/parts/{key}_{i}.png'
        ent['parts'].append({'file':out,'w':round(w/2,1),'h':round(h/2,1),'ax':round(ax*k/2,1),'ay':round(ay*k/2,1),'cx':round(cx,1),'cy':round(cy,1)})
    im.save(GAME+'/'+out,optimize=True)
for e in man.values(): e['parts'].sort(key=lambda p:p['cy'])      # дальние (выше) — первыми
p=GAME+'/src/sprites-data.js'; s=open(p).read()
s=re.sub(r'\nSPRITE_DATA\.coverParts = .*','',s,flags=re.S)
s+="\nSPRITE_DATA.coverParts = "+json.dumps(man,ensure_ascii=False)+";\n"
open(p,'w').write(s); print(len(man),'plants')
