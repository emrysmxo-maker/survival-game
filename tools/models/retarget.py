import sys,json; sys.path.insert(0,'/tmp/claude-0/gp')
from glbutil import *
UAL='/tmp/claude-0/gp/ual/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb'
SOL='/home/user/survival-game/godot/assets/character/Soldier.glb'
MAP={'hips':'Hips','spine.001':'Spine','spine.002':'Spine1','spine.003':'Spine2','neck':'Neck','head':'Head'}
for s,m in (('L','Left'),('R','Right')):
    MAP.update({f'shoulder.{s}':f'{m}Shoulder',f'upper_arm.{s}':f'{m}Arm',f'forearm.{s}':f'{m}ForeArm',f'hand.{s}':f'{m}Hand',
                f'thigh.{s}':f'{m}UpLeg',f'shin.{s}':f'{m}Leg',f'foot.{s}':f'{m}Foot',f'toe.{s}':f'{m}ToeBase'})
uj,ub=load(UAL); sj,sb=load(SOL)
un=uj['nodes']; sn=sj['nodes']
def parents(nodes):
    p={}
    for i,n in enumerate(nodes):
        for c in n.get('children',[]): p[c]=i
    return p
up,sp=parents(un),parents(sn)
unames={n.get('name'):i for i,n in enumerate(un)}; snames={n.get('name'):i for i,n in enumerate(sn)}
def order(nodes,par):
    # топологический порядок (родитель раньше)
    res=[];seen=set()
    def go(i):
        if i in seen: return
        if i in par: go(par[i])
        seen.add(i); res.append(i)
    for i in range(len(nodes)): go(i)
    return res
uord,sord=order(un,up),order(sn,sp)
def lrot(n): return np.array(n.get('rotation',[0,0,0,1]),dtype=float)
def ltr(n): return np.array(n.get('translation',[0,0,0]),dtype=float)
def lsc(n): s=n.get('scale',[1,1,1]); return float(np.mean(s))
def globals_(nodes,par,ordr,rots,trs):
    G={}  # i -> (rot,pos,scale)
    for i in ordr:
        r,t,s=rots[i],trs[i],lsc(nodes[i])
        if i in par:
            pr,pp,ps=G[par[i]]
            G[i]=(qmul(pr,r),pp+qrot(pr,t*ps),ps*s)
        else: G[i]=(r,t,s)
    return G
u_rest_r={i:lrot(un[i]) for i in range(len(un))}; u_rest_t={i:ltr(un[i]) for i in range(len(un))}
s_rest_r={i:lrot(sn[i]) for i in range(len(sn))}; s_rest_t={i:ltr(sn[i]) for i in range(len(sn))}
UG0=globals_(un,up,uord,u_rest_r,u_rest_t); SG0=globals_(sn,sp,sord,s_rest_r,s_rest_t)
RY=np.array([0,1.0,0,0])  # 180° вокруг Y: x,y,z,w
shipx=snames["mixamorig:Hips"]
uhip=unames['DEF-hips']; ship=snames['mixamorig:Hips']
k=SG0[ship][1][1]/UG0[uhip][1][1]
print('k',k)
def slerp(a,b,t):
    d=np.dot(a,b)
    if d<0: b=-b; d=-d
    if d>0.9995: r=a+t*(b-a); return r/np.linalg.norm(r)
    th=np.arccos(d); return (np.sin((1-t)*th)*a+np.sin(t*th)*b)/np.sin(th)
anims={a['name']:a for a in uj['animations']}
out={'fps':30,'clips':{}}
for cname,outname in (('Swim_Fwd_Loop','Swim_Fwd'),('Swim_Idle_Loop','Swim_Idle')):
    A=anims[cname]; ch={}
    tmax=0
    for c in A['channels']:
        s=A['samplers'][c['sampler']]
        times=acc(uj,ub,s['input'])[:,0]; vals=acc(uj,ub,s['output'])
        ch[(c['target']['node'],c['target']['path'])]=(times,vals); tmax=max(tmax,times[-1])
    n=int(round(tmax*30))+1; frames=[]
    def sample(key,t,default):
        if key not in ch: return default
        times,vals=ch[key]
        if t>=times[-1]: return vals[-1]
        idx=int(np.searchsorted(times,t,side='right'))-1; idx=max(idx,0)
        f=(t-times[idx])/max(times[idx+1]-times[idx],1e-9)
        if key[1]=='rotation': return slerp(vals[idx],vals[idx+1],f)
        return vals[idx]*(1-f)+vals[idx+1]*f
    res={}
    for fi in range(n):
        t=fi/30.0
        ur={i:np.array(sample((i,'rotation'),t,u_rest_r[i]),dtype=float) for i in range(len(un))}
        ut={i:np.array(sample((i,'translation'),t,u_rest_t[i]),dtype=float) for i in range(len(un))}
        UG=globals_(un,up,uord,ur,ut)
        # целевой скелет
        sr=dict(s_rest_r); st=dict(s_rest_t); SG={}
        for i in sord:
            name=sn[i].get('name','')
            src=None
            if name.startswith('mixamorig:') and name[10:] in MAP.values():
                inv={v:k_ for k_,v in MAP.items()}; src=unames['DEF-'+inv[name[10:]]]
            if src is not None:
                D=qmul(UG[src][0],qinv(UG0[src][0]))            # поворот в пространстве модели
                Dt=qmul(qmul(RY,D),qinv(RY))
                Gt=qmul(Dt,SG0[i][0])
                if i in sp:
                    pr,pp,ps=SG[sp[i]]; loc=qmul(qinv(pr),Gt)
                else: loc=Gt
                sr[i]=loc/np.linalg.norm(loc)
                if name=="mixamorig:Hips":
                    dp=UG[src][1]-UG0[src][1]; dp=np.array([-dp[0],dp[1],-dp[2]])*k   # поворот на 180° вокруг Y
                    tp=SG0[i][1]+dp
                    pr,pp,ps=SG[sp[i]]
                    st[i]=qrot(qinv(pr),tp-pp)/ps
            if i in sp:
                pr,pp,ps=SG[sp[i]]; SG[i]=(qmul(pr,sr[i]),pp+qrot(pr,st[i]*ps),ps*lsc(sn[i]))
            else: SG[i]=(sr[i],st[i],lsc(sn[i]))
        for i in sord:
            name=sn[i].get('name','')
            if name.startswith('mixamorig:') and name[10:] in MAP.values():
                res.setdefault('mixamorig_'+name[10:],[]).append([round(float(x),5) for x in sr[i]])
                if name=='mixamorig:Hips': res.setdefault('mixamorig_Hips_pos',[]).append([round(float(x),4) for x in st[i]])
    out['clips'][outname]={'len':float(tmax),'n':int(n),'tracks':res}
    print(outname,tmax,n,res["mixamorig_Hips_pos"][0],list(s_rest_t[shipx]))
json.dump(out,open('/tmp/claude-0/gp/swim.json','w'))
