"""Текстура земли: фото (diffuse) + впечённый свет из карты нормалей (nor_gl),
свет слева-сверху экрана (мир -1,-1) — камешки/листья/комья получают объём.
Размер 384 (GROUND_TEX_PX)."""
import numpy as np
from PIL import Image, ImageEnhance
OUT='/home/user/survival-game/assets/ground/'
ADJ={'swamp':(0.95,1),'riverbed':(0.9,1),'rocky':(0.58,0.75)}
L=np.array([-0.55,-0.55,0.63]); L=L/np.linalg.norm(L)
for k in ['grass','light','path','dark','ash','swamp','riverbed','rocky']:
    d=Image.open(f'{k}_d.jpg').convert('RGB').resize((384,384),Image.LANCZOS)
    n=np.array(Image.open(f'{k}_n.jpg').convert('RGB').resize((384,384),Image.LANCZOS)).astype(np.float32)/255*2-1
    nx,ny,nz=n[:,:,0],-n[:,:,1],n[:,:,2]                 # GL: зелёный вверх -> ось картинки вниз
    shade=(nx*L[0]+ny*L[1]+nz*L[2])/L[2]                  # 1 на ровном
    f=np.clip(0.55+0.45*shade,0.35,1.45)[:,:,None]
    a=np.array(d).astype(np.float32)*f
    im=Image.fromarray(a.clip(0,255).astype(np.uint8))
    b,c=ADJ.get(k,(1,1))
    if c!=1: im=ImageEnhance.Contrast(im).enhance(c)
    if b!=1: im=ImageEnhance.Brightness(im).enhance(b)
    # подогнать среднюю яркость к прежней текстуре, чтобы биомы не поменяли тон
    old=np.array(Image.open(OUT+k+'.jpg').convert('RGB')).astype(np.float32).mean((0,1))
    new=np.array(im).astype(np.float32).mean((0,1))
    im=Image.fromarray((np.array(im).astype(np.float32)*(old/new)).clip(0,255).astype(np.uint8))
    im.save(OUT+k+'.jpg',quality=86)
    print(k,'ok')
