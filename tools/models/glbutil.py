import json,struct,numpy as np
def load(path):
    b=open(path,'rb').read(); l=struct.unpack('<I',b[12:16])[0]; j=json.loads(b[20:20+l])
    off=20+l; 
    while off<len(b):
        cl,ct=struct.unpack('<II',b[off:off+8])
        if ct==0x004E4942: bin_=b[off+8:off+8+cl]; break
        off+=8+cl
    return j,bin_
def acc(j,bin_,i):
    a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    dt={5126:np.float32,5123:np.uint16,5125:np.uint32,5121:np.uint8}[a['componentType']]
    o=bv.get('byteOffset',0)+a.get('byteOffset',0)
    return np.frombuffer(bin_,dtype=dt,count=a['count']*n,offset=o).reshape(a['count'],n)
def qmul(a,b):
    x1,y1,z1,w1=a; x2,y2,z2,w2=b
    return np.array([w1*x2+x1*w2+y1*z2-z1*y2, w1*y2-x1*z2+y1*w2+z1*x2, w1*z2+x1*y2-y1*x2+z1*w2, w1*w2-x1*x2-y1*y2-z1*z2])
def qinv(a): return np.array([-a[0],-a[1],-a[2],a[3]])
def qrot(q,v):
    u=np.array(q[:3]); w=q[3]
    return 2*np.dot(u,v)*u+(w*w-np.dot(u,u))*v+2*w*np.cross(u,v)
