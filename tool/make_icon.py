"""Renders assets/icon.png and assets/icon_foreground.png (1024px) for SUDOSEND."""
from PIL import Image, ImageDraw, ImageFilter
import math, os

S = 1024
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets')

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(size, c1, c2):
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            px[x, y] = lerp(c1, c2, t)
    return img

def bolt(draw, cx, cy, scale, fill):
    pts = [(0.10, -0.50), (-0.28, 0.06), (-0.02, 0.06), (-0.12, 0.50), (0.28, -0.08), (0.02, -0.08), (0.10, -0.50)]
    draw.polygon([(cx + x * scale, cy + y * scale) for x, y in pts], fill=fill)

def render(foreground_only=False):
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    if not foreground_only:
        bg = Image.new('RGBA', (S, S), (6, 8, 22, 255))
        # neon orbs
        glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        g = ImageDraw.Draw(glow)
        g.ellipse((-200, -200, 620, 620), fill=(139, 92, 246, 170))
        g.ellipse((420, 380, 1240, 1200), fill=(56, 225, 255, 140))
        glow = glow.filter(ImageFilter.GaussianBlur(140))
        bg = Image.alpha_composite(bg, glow)
        mask = Image.new('L', (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=230, fill=255)
        img.paste(bg, (0, 0), mask)
    # glass disc
    inner = 560 if not foreground_only else 600
    off = (S - inner) // 2
    disc = gradient(inner, (56, 225, 255), (139, 92, 246)).convert('RGBA')
    dmask = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(dmask).ellipse((0, 0, inner - 1, inner - 1), fill=255)
    halo = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse((off - 30, off - 30, off + inner + 30, off + inner + 30), fill=(56, 225, 255, 120))
    halo = halo.filter(ImageFilter.GaussianBlur(50))
    img = Image.alpha_composite(img, halo)
    img.paste(disc, (off, off), dmask)
    d = ImageDraw.Draw(img)
    bolt(d, S / 2, S / 2, inner * 0.78, (7, 10, 22, 255))
    return img

os.makedirs(OUT, exist_ok=True)
render().save(os.path.join(OUT, 'icon.png'))
render(foreground_only=True).save(os.path.join(OUT, 'icon_foreground.png'))
print('ok')
