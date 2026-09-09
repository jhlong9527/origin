"""Original 1024px environment surface studies: stone, cut timber and patinated copper."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'environment'
OUT.mkdir(parents=True, exist_ok=True)
N = 1024
rng = np.random.default_rng(180908)
y, x = np.mgrid[:N, :N] / N

def noise(cells):
    tile = rng.random((cells, cells))
    px, py = x*cells, y*cells
    ix, iy = px.astype(int), py.astype(int)
    fx, fy = px-ix, py-iy
    fx, fy = fx*fx*(3-2*fx), fy*fy*(3-2*fy)
    return (tile[iy%cells,ix%cells]*(1-fx)+tile[iy%cells,(ix+1)%cells]*fx)*(1-fy)+(tile[(iy+1)%cells,ix%cells]*(1-fx)+tile[(iy+1)%cells,(ix+1)%cells]*fx)*fy

def save(name, image):
    if image.ndim == 2:
        image = np.repeat(image[..., None], 3, axis=2)
    Image.fromarray(np.uint8(np.clip(image,0,1)*255)).save(OUT/(name+'.png'))

def surface(name, height, color, roughness, strength):
    dx=(np.roll(height,-1,1)-np.roll(height,1,1))*strength
    dy=(np.roll(height,-1,0)-np.roll(height,1,0))*strength
    normal=np.stack((-dx,-dy,np.ones_like(height)),axis=2)
    normal/=np.linalg.norm(normal,axis=2,keepdims=True)
    save(name+'_albedo',color)
    save(name+'_normal',normal*.5+.5)
    save(name+'_roughness',roughness)

coarse=noise(9); medium=noise(38); fine=noise(180)
pores=np.clip((noise(250)-.7)*3,0,1)
vein=np.abs(np.sin((x*4.1+y*1.7+noise(7)*.53)*np.pi))
vein=np.exp(-vein*85)
chisel=np.maximum(0,np.sin((x*71+y*2+noise(7)*.1)*np.pi*2))*.025
stone=.55+coarse*.13+medium*.12+fine*.07-pores*.18-vein*.15-chisel
surface('carved_stone',stone,(.72+stone*.29-vein*.1)[...,None]*np.array([.98,1.0,.97]),.86+medium*.10,3.2)

# Timber has longitudinal pores, curving annual bands and small darker pin knots.
warp=noise(5)*.17+np.sin(y*np.pi*2)*.009
grain=np.sin((x+warp)*np.pi*2*67)
grain=np.maximum(0,grain)**7
deep=np.maximum(0,np.sin((x+warp*.7)*np.pi*2*19))**20
height=.58+noise(72)*.06-grain*.10-deep*.15
color=.70+noise(13)*.16-grain*.075-deep*.12
for cx,cy in [(0.24,.28),(.73,.71),(.45,.86)]:
    d=np.sqrt(((x-cx)/.024)**2+((y-cy)/.065)**2)
    knot=np.exp(-d*1.5)
    ring=np.exp(-abs(d-1.3)*4)
    height-=knot*.2+ring*.065
    color-=knot*.24+ring*.09
surface('weathered_wood',height,color[...,None]*np.array([1.0,.93,.82]),.83+noise(35)*.13,2.8)

# Mineral bloom breaks through the rubbed bronze on exposed lantern metal.
oxidation=np.clip((noise(9)*.6+noise(42)*.4-.22)*3.0,0,1)
wear=noise(65); hammered=noise(110)
copper=np.array([.48,.34,.22])[None,None,:]
patina=np.array([.22,.46,.38])[None,None,:]
color=copper*(1-oxidation[...,None])+patina*oxidation[...,None]
color*=.85+wear[...,None]*.25
surface('aged_copper',.48+hammered*.09+oxidation*.035,color,.47+oxidation*.37+wear*.07,1.0)

soft=noise(17); fibers=noise(200)
surface('moss',.53+fibers*.24+soft*.19,(.68+soft*.24+fibers*.06)[...,None]*np.array([.69,.84,.43]),.96+soft*.025,3.1)
print('Generated', len(list(OUT.glob('*.png'))), 'original environment maps at 1024 px')
