import json
H=lambda h:int(h,16)
S={}
def add(n,preset,height,seed,maxW,**o):
    S[n]={"preset":preset,"height":height,"seed":seed,"maxW":maxW,"opts":{k.replace('__','.'):v for k,v in o.items()}}
add("00_pine","Pine Medium",12,2,4.6,bark__tint=H("d9a070"),leaves__count=50,leaves__size=1.7,leaves__tint=H("c8e0b0"))
add("01_oak","Pine Medium" if False else "Oak Medium",9.5,3,5.5,leaves__count=42,leaves__size=3.0,leaves__tint=H("f0f0e0"))
add("02_birch","Aspen Medium",11,7,4.4,bark__type="birch",bark__tint=H("ffffff"),leaves__tint=H("8fd040"),leaves__count=40,leaves__size=2.5)
add("03_maple","Oak Medium",9.5,11,5.2,leaves__tint=H("e8f0c0"),leaves__count=44,leaves__size=3.1)
add("04_deadwood","Ash Medium",9.5,13,5.2,leaves__count=0,bark__tint=H("d8d0c8"),branch__radius__1=1.1,branch__radius__2=0.9)
add("05_bluespruce","Pine Medium",11,5,4.0,leaves__tint=H("a0c8e8"),leaves__count=56,leaves__size=1.6,bark__tint=H("b0a898"))
add("06_willow","Ash Medium",9,17,5.5,bark__type="willow",leaves__tint=H("e0f0a0"),leaves__count=44,leaves__size=2.3,branch__force__strength=-0.25)
add("07_aspen","Aspen Medium",10.5,4,4.6,leaves__tint=H("90d040"),leaves__count=36,leaves__size=2.5)
add("08_rowan","Ash Small",7.5,19,4.6,leaves__tint=H("f0f8d0"),leaves__count=34,leaves__size=2.7)
add("09_cedar","Pine Medium",11.5,23,5.0,leaves__tint=H("88a880"),leaves__count=58,leaves__size=1.8,bark__tint=H("a07050"))
add("10_larch","Pine Medium",12,29,4.6,leaves__tint=H("e0f0a0"),leaves__count=40,leaves__size=1.7)
add("11_linden","Ash Medium",9.5,31,5.4,leaves__tint=H("d8f0a8"),leaves__count=48,leaves__size=3.0)
json.dump(S,open('s4.json','w'),indent=1)
