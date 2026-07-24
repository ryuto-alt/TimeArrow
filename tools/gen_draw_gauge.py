# gen_draw_gauge.py -- 弓引き絞りゲージ(時計盤)のUIテクスチャ生成
# 出力: assets/textures/ui_gauge_dial_rgba.png / ui_gauge_arc_rgba.png / ui_gauge_hand_rgba.png
# 世界観=時計仕掛け: ダークネイビーの盤面+真鍮リング+目盛り。針は別画像(setUiRotationで回す)。
# 4xスーパーサンプリングで描いて縮小(エッジAA)。
import math
import os
from PIL import Image, ImageDraw

S = 1024          # 作業解像度
OUT = 256         # 出力解像度
C = S / 2

BRASS_HI = (214, 178, 116)
BRASS_LO = (122, 95, 51)
BRASS = (168, 136, 82)
NAVY = (14, 20, 40)
NAVY_EDGE = (8, 12, 26)
TICK_MINOR = (74, 90, 128)
CYAN = (85, 224, 255)


def annulus_mask(size, r_out, r_in):
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([C - r_out, C - r_out, C + r_out, C + r_out], fill=255)
    d.ellipse([C - r_in, C - r_in, C + r_in, C + r_in], fill=0)
    return m


def vgrad(size, top, bottom):
    g = Image.new('RGBA', (size, size))
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        ImageDraw.Draw(g).line([(0, y), (size, y)], fill=c + (255,))
    return g


def gen_dial():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 盤面(ネイビー、外周をわずかに暗く)
    d.ellipse([C - 436, C - 436, C + 436, C + 436], fill=NAVY_EDGE + (235,))
    d.ellipse([C - 420, C - 420, C + 420, C + 420], fill=NAVY + (235,))
    # 真鍮外リング(縦グラデ)
    ring = vgrad(S, BRASS_HI, BRASS_LO)
    img.paste(ring, (0, 0), annulus_mask(S, 480, 436))
    # 目盛り: 60分割(細) + 12分割(太・真鍮)
    for i in range(60):
        a = math.radians(i * 6 - 90)
        major = (i % 5 == 0)
        r0 = 388 if major else 404
        r1 = 424
        w = 10 if major else 4
        col = BRASS if major else TICK_MINOR
        d.line([(C + math.cos(a) * r0, C + math.sin(a) * r0),
                (C + math.cos(a) * r1, C + math.sin(a) * r1)], fill=col + (255,), width=w)
    # 12時のアクセント(シアンのひし形)=ゲージの始点
    dy = 448
    d.polygon([(C, C - dy - 22), (C + 16, C - dy), (C, C - dy + 22), (C - 16, C - dy)],
              fill=CYAN + (255,))
    # 中央ハブ
    d.ellipse([C - 26, C - 26, C + 26, C + 26], fill=BRASS + (255,))
    d.ellipse([C - 12, C - 12, C + 12, C + 12], fill=BRASS_LO + (255,))
    return img


def gen_arc():
    # 白のリング(radial fillで扇形に切られ、uiImage colorでシアン/紫に着色される)
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    white = Image.new('RGBA', (S, S), (255, 255, 255, 255))
    img.paste(white, (0, 0), annulus_mask(S, 380, 312))
    return img


def gen_hand():
    # 中心から上向きの時計針。画像中心が回転軸(setUiRotation)
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 針本体(先細り)
    d.polygon([(C - 16, C), (C + 16, C), (C + 5, C - 350), (C - 5, C - 350)],
              fill=(255, 255, 255, 255))
    # 先端のひし形
    d.polygon([(C, C - 392), (C + 14, C - 350), (C, C - 322), (C - 14, C - 350)],
              fill=(255, 255, 255, 255))
    # 尾(カウンターウェイト)
    d.polygon([(C - 12, C), (C + 12, C), (C + 7, C + 90), (C - 7, C + 90)],
              fill=(255, 255, 255, 255))
    d.ellipse([C - 24, C + 78, C + 24, C + 126], fill=(255, 255, 255, 255))
    # 軸穴
    d.ellipse([C - 14, C - 14, C + 14, C + 14], fill=(0, 0, 0, 0))
    return img


def save(img, name):
    out_dir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'textures')
    img.resize((OUT, OUT), Image.LANCZOS).save(os.path.join(out_dir, name))
    print('saved', name)


if __name__ == '__main__':
    save(gen_dial(), 'ui_gauge_dial_rgba.png')
    save(gen_arc(), 'ui_gauge_arc_rgba.png')
    save(gen_hand(), 'ui_gauge_hand_rgba.png')
