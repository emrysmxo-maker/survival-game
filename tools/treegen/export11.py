"""Рендеры деревьев Poly Haven (outs/*.png, s11.json) -> assets/trees/ (360x720) с цветокоррекцией.
Осенние (03_maple, 08_rowan): листья зелёные -> оранжево-красные сдвигом оттенка."""
import numpy as np, os
from PIL import Image
OUT='/home/user/survival-game/assets/trees'
AUTUMN={'03_maple':(0.05,1.3,1.1),'08_rowan':(0.075,1.2,0.95),'07_aspen':(0.15,1.1,1.1)}   # целевой оттенок, насыщенность, яркость
BRIGHT={'00_pine':1.7,'05_bluespruce':1.7,'09_cedar':1.2,'10_larch':1.2}
def grade(im,k):
    a=np.array(im.convert('RGBA')).astype(np.float32); rgb=a[:,:,:3]/255.0
    mx=rgb.max(2); mn=rgb.min(2); d=mx-mn+1e-6
    r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    h=np.where(mx==r,((g-b)/d)%6,np.where(mx==g,(b-r)/d+2,(r-g)/d+4))/6.0
    s=d/(mx+1e-6); v=mx
    if k in AUTUMN:
        th,sm,vm=AUTUMN[k]
        mask=(s>0.15)&(h>0.12)&(h<0.5)
        h=np.where(mask,th+(h-0.25)*0.25,h); s=np.where(mask,np.clip(s*sm,0,1),s); v=np.where(mask,np.clip(v*vm*1.15,0,1),v)
    v=np.clip(v*BRIGHT.get(k,1.15),0,1)
    i=np.floor(h*6).astype(int)%6; f=h*6-np.floor(h*6)
    p=v*(1-s); q=v*(1-f*s); t=v*(1-(1-f)*s)
    R=np.choose(i,[v,q,p,p,t,v]); G=np.choose(i,[t,v,v,q,p,p]); B=np.choose(i,[p,p,t,v,v,q])
    rgb=np.stack([R,G,B],2)
    gr=rgb.mean(2,keepdims=True); rgb=(gr+(rgb-gr)*0.92)*0.97          # чуть приглушить под фон
    a[:,:,:3]=rgb*255
    return Image.fromarray(a.clip(0,255).astype(np.uint8),'RGBA')
for f in sorted(os.listdir('outs')):
    if not f.endswith('.png'): continue
    k=f[:-4]
    im=grade(Image.open('outs/'+f),k).resize((360,720),Image.LANCZOS)
    im.save(OUT+'/'+k+'.png')
    al=np.array(im.getchannel('A')); row=al[int(0.9*720)-14]        # ширина ствола у земли
    xs=np.nonzero(row>128)[0]
    print(k,'trunk w frac',round((xs.max()-xs.min()+1)/360,3) if len(xs) else None)
