import requests, os, sys, json
H={'User-Agent':'Mozilla/5.0'}
for a in sys.argv[1:]:
    d=requests.get(f'https://api.polyhaven.com/files/{a}',headers=H,timeout=30).json()
    g=d['gltf']; import os as _o
    res=_o.environ.get('RES','1k'); res=res if res in g else sorted(g)[-1]
    ent=g[res]['gltf']; base=_o.environ.get('BASE','plants')+f'/{a}'; os.makedirs(base,exist_ok=True)
    def get(url,path):
        os.makedirs(os.path.dirname(path),exist_ok=True)
        open(path,'wb').write(requests.get(url,headers=H,timeout=120).content)
    get(ent['url'],f'{base}/{a}.gltf')
    for rel,inc in ent.get('include',{}).items(): get(inc['url'],f'{base}/{rel}')
    print(a,res,'ok',sum(len(f) for _,_,f in os.walk(base)))
