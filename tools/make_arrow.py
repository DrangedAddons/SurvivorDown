# SurvivorDown's list arrow: gold navigation arrow pointing up, black outline, its bounding
# box centred on the image so it turns about its own middle.
import sys
sys.path.insert(0, '.')
import numpy as np, blp
from PIL import Image, ImageDraw, ImageFilter

N, K = 64, 8  # final size, supersampling
S = N * K
pts = [(32, 10), (50, 52), (32, 42), (14, 52)]  # tip, right back, notch, left back; inside r=27 so turning never clips
box_mid = (10 + 52) / 2
pts = [(x, y - box_mid + 31.5) for x, y in pts]  # centre the bounding box vertically
P = [(x * K, y * K) for x, y in pts]

def poly_mask(width):
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)
    d.polygon(P, fill=255)
    if width:
        d.line(P + [P[0]], fill=255, width=width * K, joint='curve')
    return m

fill = poly_mask(0)
outline = poly_mask(4)                     # black rim
shadow = poly_mask(7).filter(ImageFilter.GaussianBlur(2 * K))  # soft dark halo for busy ground

img = np.zeros((S, S, 4), np.float32)
sh = np.asarray(shadow, np.float32) / 255 * 0.6
img[..., 3] = sh * 255
ol = np.asarray(outline, np.float32) / 255
img[..., :3] *= 1 - ol[..., None]
img[..., 3] = np.maximum(img[..., 3], ol * 255)
fl = np.asarray(fill, np.float32) / 255
# gold, a little brighter toward the tip
y = np.mgrid[0:S, 0:S][0] / S
gold = np.stack([np.full_like(y, 255), 225 - 50 * y, 40 + 0 * y], -1)
img[..., :3] = img[..., :3] * (1 - fl[..., None]) + gold * fl[..., None]
img[..., 3] = np.maximum(img[..., 3], fl * 255)
out = Image.fromarray(img.clip(0, 255).astype(np.uint8)).resize((N, N), Image.LANCZOS)
arr = np.asarray(out)
blp.write(sys.argv[1] if len(sys.argv) > 1 else 'Arrow.blp', arr)
