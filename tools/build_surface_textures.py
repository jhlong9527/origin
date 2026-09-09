"""Deterministic, tileable original surface maps. No external assets required."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'surfaces'
OUT.mkdir(parents=True, exist_ok=True)
N = 512
rng = np.random.default_rng(70821)
y, x = np.mgrid[:N, :N] / N

def noise(cells):
    tile = rng.random((cells, cells))
    px, py = x*cells, y*cells
    ix, iy = px.astype(int), py.astype(int)
    fx, fy = px-ix, py-iy
    fx, fy = fx*fx*(3-2*fx), fy*fy*(3-2*fy)
    return ((tile[iy % cells, ix % cells]*(1-fx)+tile[iy % cells,(ix+1)%cells]*fx)*(1-fy)
            +(tile[(iy+1)%cells,ix % cells]*(1-fx)+tile[(iy+1)%cells,(ix+1)%cells]*fx)*fy)

def save(name, value):
    a = np.asarray(value)
    if a.ndim == 2: a = np.repeat(a[:,:,None],3,axis=2)
    Image.fromarray(np.uint8(np.clip(a,0,1)*255)).save(OUT / (name+'.png'))

def surface(name, h, tint, strength=1.0, rough=.8):
    save(name+'_albedo', tint)
    dx = (np.roll(h,-1,1)-np.roll(h,1,1))*strength
    dy = (np.roll(h,-1,0)-np.roll(h,1,0))*strength
    normal = np.stack((-dx,-dy,np.ones_like(h)),axis=2)
    normal /= np.linalg.norm(normal,axis=2,keepdims=True)
    save(name+'_normal',normal*.5+.5)
    save(name+'_roughness', np.clip(rough+(h-.5)*.16,0,1))

coarse, fine = noise(8), noise(110)
stone = .36*coarse+.28*noise(24)+.36*fine
cracks = Image.new('L',(N,N),0)
d = ImageDraw.Draw(cracks)
for i in range(13):
    p = rng.integers(0,N,2).astype(float)
    pts=[tuple(p)]
    for j in range(int(rng.integers(3,7))):
        p += rng.normal(0,16,2)+[12,6]
        pts.append(tuple(p))
    d.line(pts,fill=175,width=1)
crack=np.asarray(cracks)/255
surface('stone',stone-crack*.32,.72+stone*.26-crack*.28,2.6,.88)
soil=.48*noise(11)+.32*noise(47)+.2*fine
pebbles = np.maximum(0,noise(53)-.68)*2.2
surface('soil',soil+pebbles,.69+soil*.25+pebbles*.09,2.7,.94)
brush=.035*np.sin(x*np.pi*2*139)+noise(112)*.08
metal=.50+brush+noise(8)*.12
scratches=np.maximum(0,np.sin((x*117+noise(8)*.2)*np.pi*2)-.99)*13
wear=Image.new('L',(N,N),0)
wd=ImageDraw.Draw(wear)
for i in range(38):
    sx,sy=rng.integers(8,N-45,2)
    wd.line([(int(sx),int(sy)),(int(sx+rng.integers(9,38)),int(sy+rng.integers(-5,6)))],fill=int(rng.integers(70,180)),width=1)
wear=np.asarray(wear)/255
surface('metal',metal-scratches*.17-wear*.22,.81+metal*.20-scratches*.22-wear*.22,1.4,.55)
weave=(np.sin(x*np.pi*2*22)*np.cos(y*np.pi*2*22))*.19
cloth=.52+weave+noise(30)*.12
surface('cloth',cloth,.79+cloth*.22,2.0,.96)
grain=np.sin((x*28+noise(6)*1.3+np.sin(y*12.56)*.2)*np.pi*2)
bark=.45+grain*.18+noise(50)*.17
surface('bark',bark,.64+bark*.38,3.2,.92)
# A shared folded-leaf map: midrib, angled secondary veins, soft mottled lamina.
mid=np.exp(-((x-.5)/.016)**2)
veins=np.exp(-(np.sin((y*10+np.abs(x-.5)*5)*np.pi)/.15)**2)
leaf=.62+noise(9)*.21+mid*.12+veins*.045
surface('leaf',leaf,leaf+.10,1.7,.83)
print('Wrote',len(list(OUT.glob('*.png'))),'original 512px maps to',OUT)
