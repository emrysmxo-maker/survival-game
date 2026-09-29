import numpy as np, colorsys, os
from PIL import Image
OUT="/home/user/survival-game/assets/trees"
HUE={'02_birch':0.075,'07_aspen':0.075}   # сдвиг оттенка листвы к зелёному (доля круга)
def grade(im,k):
    im=im.convert('RGBA'); a=np.array(im).astype(np.float32)
    if k in HUE:
        rgb=a[:,:,:3]/255.0
        mx=rgb.max(2); mn=rgb.min(2); d=mx-mn+1e-6
        r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
        h=np.where(mx==r,((g-b)/d)%6,np.where(mx==g,(b-r)/d+2,(r-g)/d+4))/6.0
        # сдвигаем только жёлто-оливковые (0.10–0.22), ствол (серый) не трогаем
        sat=d/(mx+1e-6)
        mask=(sat>0.25)&(h>0.10)&(h<0.24)
        h2=np.where(mask,h+HUE[k],h)
        s=sat; v=mx
        i=np.floor(h2*6).astype(int)%6; f=h2*6-np.floor(h2*6)
        p=v*(1-s); q=v*(1-f*s); t=v*(1-(1-f)*s)
        R=np.choose(i,[v,q,p,p,t,v]); G=np.choose(i,[t,v,v,q,p,p]); B=np.choose(i,[p,p,t,v,v,q])
        a[:,:,:3]=np.stack([R,G,B],2)*255
    # общая цветокоррекция под фон: чуть приглушить насыщенность и яркость
    rgb=a[:,:,:3]/255.0; g=rgb.mean(2,keepdims=True)
    rgb=(g+(rgb-g)*0.85)*0.93
    a[:,:,:3]=rgb*255
    return Image.fromarray(a.clip(0,255).astype(np.uint8),'RGBA')
for f in sorted(os.listdir('out')):
    if not f.endswith('.png'): continue
    k=f[:-4]; broken=k.startswith('b_'); name=k[2:] if broken else k
    im=grade(Image.open('out/'+f),name).resize((360,500),Image.LANCZOS)
    dst=(OUT+'/broken/' if broken else OUT+'/')+name+'.png'
    im.save(dst)
print('exported')
