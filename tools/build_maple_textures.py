"""Original maple lamina and golden petal detail, deterministic and reproducible.

Textures are neutral so mesh vertex colors can provide autumn color variation.
The maple UV origin is the stem at (.5, .04), with the central tip at (.5, .98).
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'surfaces'
OUT.mkdir(parents=True, exist_ok=True)
N = 1024
rng = np.random.default_rng(90427)
y, x = np.mgrid[:N, :N] / (N - 1)

def lines(paths, width):
    canvas = Image.new('L', (N, N), 0)
    draw = ImageDraw.Draw(canvas)
    for points in paths:
        draw.line([(round(px * (N - 1)), round(py * (N - 1))) for px, py in points], fill=255, width=width, joint='curve')
    return np.asarray(canvas.filter(ImageFilter.GaussianBlur(.7)), dtype=float) / 255

def smooth_noise(size):
    a = Image.fromarray(np.uint8(rng.random((size, size)) * 255))
    return np.asarray(a.resize((N, N), Image.Resampling.BICUBIC), dtype=float) / 255

def save_surface(name, tone, height, roughness):
    # Grain is intentionally subtle to preserve crisp, readable silhouettes.
    rgb = np.repeat(np.clip(tone, 0, 1)[:, :, None], 3, axis=2)
    Image.fromarray(np.uint8(rgb * 255)).save(OUT / f'{name}_albedo.png')
    dy, dx = np.gradient(height)
    normal = np.stack((-dx * 5, -dy * 5, np.ones_like(height)), axis=2)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    Image.fromarray(np.uint8((normal * .5 + .5) * 255)).save(OUT / f'{name}_normal.png')
    Image.fromarray(np.uint8(np.clip(roughness, 0, 1) * 255)).save(OUT / f'{name}_roughness.png')

hub = np.array([.5, .23])
tips = [(.5, .97), (.19, .79), (.81, .79), (.035, .49), (.965, .49), (.23, .22), (.77, .22)]
main, secondary, fine = [], [], []
main.append([(.5, .02), tuple(hub)])
for tip in tips:
    tip = np.array(tip)
    axis = tip - hub
    side = np.array([-axis[1], axis[0]])
    main.append([tuple(hub), tuple(tip)])
    for t in np.linspace(.25, .84, 7):
        at = hub + axis * t
        for sign in [-1, 1]:
            end = at + axis * .09 + side * sign * (.16 * (1 - t) + .055)
            secondary.append([tuple(at), tuple((at + end) * .5 + axis * .015), tuple(end)])
            for j in [.4, .68]:
                q = at + (end - at) * j
                fine.append([tuple(q), tuple(q + axis * .045 + side * sign * .025)])
vein, sub, net = lines(main, 5), lines(secondary, 2), lines(fine, 1)
cloud = smooth_noise(22)
pores = smooth_noise(170)
tone = .69 + cloud * .18 + pores * .035 + vein * .13 + sub * .07 + net * .025
fold = np.abs(x - .5)
tone -= fold * .07
height = vein * .48 + sub * .23 + net * .07 + pores * .08
save_surface('maple', tone, height, .72 + cloud * .16 - vein * .07)

# Longitudinal striations and pollen speckling for the cupped yellow petals.
stripes = (np.cos((x - .5) * 48 + y * 5) * .5 + .5) ** 9
tip = np.clip(y, 0, 1)
petal = .71 + tip * .19 + stripes * .035 + smooth_noise(60) * .025
save_surface('petal', petal, stripes * .12 + smooth_noise(95) * .03, .70 + tip * .16)
print('Generated six original 1024px maple / petal material maps.')
