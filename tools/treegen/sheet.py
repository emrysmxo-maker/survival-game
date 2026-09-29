import sys,glob
from PIL import Image
fs=sys.argv[2:]
n=len(fs); cols=min(n,6); rows=(n+cols-1)//cols
c=Image.new('RGB',(180*cols,250*rows),(112,138,100))
for i,f in enumerate(fs):
    im=Image.open(f).convert('RGBA').resize((180,250),Image.LANCZOS)
    bg=Image.new('RGBA',im.size,(112,138,100,255)); bg.alpha_composite(im)
    c.paste(bg.convert('RGB'),((i%cols)*180,(i//cols)*250))
c=c.resize((c.width*2,c.height*2),Image.LANCZOS); c.save(sys.argv[1])
