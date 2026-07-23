# -*- coding: utf-8 -*-
"""ステージ別の空テクスチャ(自作)を assets/textures/bg_sky{n}.png へ書き出す.

Backdrop(エンジンのbox primitive)は +Z面のUVが v=1で上・D3Dは v=0が画像先頭 なので、
見た目どおりに描いてから最後に上下反転して保存する。
ステージごとにパレット/時計環/月/星密度/地平シルエットを変えて空気を差別化する:
  0 練習場   = 夜明け前。淡い月、静かな丘、星少なめ
  1 二連橋   = 黄昏シアン+金(基準)。時計環が右上
  2 閉門回廊 = 緑がかった宵。二重の時計環
  3 三つの錠 = 深い紫の夜。星が濃く、環は左
  4 動く壁   = 赤銅の終末。低く太い環、シルエット密集
"""
import numpy as np
from PIL import Image

W, H = 1024, 512

SKIES = {
    0: dict(stops=[(0.00, (10, 14, 30)), (0.45, (27, 37, 71)), (0.74, (106, 127, 174)),
                   (0.80, (184, 196, 222)), (0.86, (66, 72, 96)), (1.00, (26, 30, 46))],
            stars=90, neb=(120, 160, 220), ring=None, moon=(0.72, 0.26, 0.11),
            gears=0, sil_h=0.6, shade=(24, 32, 52)),
    1: dict(stops=[(0.00, (13, 17, 34)), (0.42, (23, 51, 79)), (0.74, (46, 115, 150)),
                   (0.80, (199, 154, 79)), (0.86, (60, 66, 90)), (1.00, (24, 28, 44))],
            stars=230, neb=(95, 194, 255), ring=[(0.70, 0.30, 0.34)], moon=None,
            gears=3, sil_h=1.0, shade=(18, 30, 46)),
    2: dict(stops=[(0.00, (8, 19, 26)), (0.42, (20, 66, 74)), (0.74, (46, 143, 122)),
                   (0.80, (199, 180, 79)), (0.86, (48, 74, 66)), (1.00, (18, 32, 30))],
            stars=170, neb=(110, 230, 190), ring=[(0.66, 0.30, 0.36), (0.66, 0.30, 0.26)],
            moon=None, gears=2, sil_h=1.0, shade=(14, 34, 30)),
    3: dict(stops=[(0.00, (18, 10, 36)), (0.42, (44, 29, 84)), (0.74, (122, 79, 160)),
                   (0.80, (192, 130, 190)), (0.86, (66, 48, 92)), (1.00, (26, 20, 44))],
            stars=340, neb=(190, 130, 255), ring=[(0.28, 0.28, 0.32)], moon=None,
            gears=2, sil_h=1.2, shade=(30, 20, 48)),
    4: dict(stops=[(0.00, (26, 11, 16)), (0.42, (74, 29, 32)), (0.74, (160, 74, 46)),
                   (0.80, (224, 138, 60)), (0.86, (84, 48, 40)), (1.00, (36, 22, 24))],
            stars=110, neb=(255, 140, 90), ring=[(0.52, 0.42, 0.46)], moon=None,
            gears=4, sil_h=1.5, shade=(40, 20, 18)),
}


def vnoise(shape, cells_x, cells_y, seed):
    r = np.random.default_rng(seed)
    g = r.random((cells_y + 1, cells_x + 1))
    ys = np.linspace(0, cells_y, shape[0], endpoint=False)
    xs = np.linspace(0, cells_x, shape[1], endpoint=False)
    yi, xi = np.floor(ys).astype(int), np.floor(xs).astype(int)
    yf, xf = ys - yi, xs - xi
    yf = yf * yf * (3 - 2 * yf); xf = xf * xf * (3 - 2 * xf)
    a = g[np.ix_(yi, xi)]; b = g[np.ix_(yi, xi + 1)]
    c = g[np.ix_(yi + 1, xi)]; d = g[np.ix_(yi + 1, xi + 1)]
    return a + (b - a) * xf[None, :] + ((c - a) + (d - c) * xf[None, :] - (b - a) * xf[None, :]) * yf[:, None]


def make_sky(n, cfg):
    rng = np.random.default_rng(20260723 + n)
    yy, xx = np.mgrid[0:H, 0:W]
    fy = yy / (H - 1)

    img = np.zeros((H, W, 3), dtype=np.float64)
    for (p0, c0), (p1, c1) in zip(cfg["stops"], cfg["stops"][1:]):
        m = (fy >= p0) & (fy <= p1)
        t = np.clip((fy - p0) / max(p1 - p0, 1e-6), 0, 1)
        for ch in range(3):
            img[:, :, ch] = np.where(m, c0[ch] + (c1[ch] - c0[ch]) * t, img[:, :, ch])

    # 風に流れる星雲のもや
    neb = (vnoise((H, W), 6, 10, n * 7 + 1) * 0.55 + vnoise((H, W), 14, 22, n * 7 + 2) * 0.30 +
           vnoise((H, W), 30, 44, n * 7 + 3) * 0.15)
    neb = np.clip((neb - 0.45) * 2.2, 0, 1) * np.clip(1.0 - fy / 0.78, 0, 1)
    for ch, c in enumerate(cfg["neb"]):
        img[:, :, ch] += neb * c * 0.16

    # 星
    sx = rng.integers(0, W, cfg["stars"])
    sy = (rng.random(cfg["stars"]) ** 1.8 * H * 0.62).astype(int)
    mag = rng.random(cfg["stars"])
    for x, y, m in zip(sx, sy, mag):
        b = 90 + 165 * m
        img[y, x] = np.maximum(img[y, x], (b * 0.85, b * 0.95, b))
        if m > 0.82:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= y + dy < H and 0 <= x + dx < W:
                    img[y + dy, x + dx] = np.maximum(img[y + dy, x + dx], (b * 0.35,) * 3)

    # 時計環の透かし(欠けあり・12目盛)
    for (rcx, rcy, rr) in (cfg["ring"] or []):
        cx, cy, r = W * rcx, H * rcy, H * rr
        dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        ring = np.exp(-((dist - r) / (H * 0.012)) ** 2)
        ang = np.arctan2(yy - cy, xx - cx)
        gap = np.clip(1.0 - np.exp(-((ang - 0.5) / 0.55) ** 2) * 0.85, 0, 1)
        ring *= gap
        for i in range(12):
            a = i * np.pi / 6
            tx, ty = cx + np.cos(a) * r, cy + np.sin(a) * r
            ring += np.exp(-(((xx - tx) ** 2 + (yy - ty) ** 2)) / (H * 0.006) ** 2) * gap
        for ch, c in enumerate((150, 210, 255)):
            img[:, :, ch] += np.clip(ring, 0, 1.4) * c * 0.10

    # 月(stage0: 夜明け前の淡い満月+うっすらクレーター)
    if cfg["moon"]:
        mcx, mcy, mr = W * cfg["moon"][0], H * cfg["moon"][1], H * cfg["moon"][2]
        dist = np.sqrt((xx - mcx) ** 2 + (yy - mcy) ** 2)
        disc = np.clip(1.0 - (dist / mr) ** 6, 0, 1)
        crat = 1.0 - 0.18 * np.clip(vnoise((H, W), 40, 60, n * 7 + 5) - 0.45, 0, 1) * 3
        halo = np.exp(-np.clip(dist - mr, 0, None) / (mr * 0.8)) * 0.25
        for ch, c in enumerate((214, 220, 236)):
            img[:, :, ch] = img[:, :, ch] * (1 - disc) + c * disc * crat
            img[:, :, ch] += c * halo * 0.35

    # 地平の遠景シルエット(尖塔遺跡+半分埋まった歯車)
    horizon = 0.80
    sil = np.zeros((H, W))
    r2 = np.random.default_rng(9 + n)
    x = 0
    dens = cfg["sil_h"]
    while x < W:
        w = int(r2.uniform(12, 38))
        h = r2.uniform(0.015, 0.055) * dens * (1 if r2.random() < 0.7 else 1.7)
        top = horizon - h
        seg = np.s_[:, x:x + w]
        body = (fy[seg] > top + h * 0.35) & (fy[seg] < horizon + 0.005)
        cx_t = x + w / 2
        taper = np.abs(xx[seg] - cx_t) / (w / 2 + 1e-6)
        spire = (fy[seg] > top) & (fy[seg] <= top + h * 0.35) & \
                (taper < np.clip((fy[seg] - top) / (h * 0.35), 0.08, 1))
        sil[seg] = np.maximum(sil[seg], (body | spire) * 1.0)
        x += w + int(r2.uniform(16, 70) / max(dens, 0.5))

    gxs = [0.18, 0.55, 0.86, 0.38][:cfg["gears"]]
    for i, gfx in enumerate(gxs):
        gx, gr = W * gfx, H * r2.uniform(0.05, 0.095)
        gy = horizon * H
        d = np.sqrt((xx - gx) ** 2 + (yy - gy) ** 2)
        a = np.arctan2(yy - gy, xx - gx)
        teeth = 1.0 + 0.10 * (np.abs(((a * 9 / np.pi) % 2) - 1) < 0.42)
        disk = (d < gr * teeth) & (d > gr * 0.55) & (yy < gy)
        hubb = (d < gr * 0.28) & (yy < gy)
        sil = np.maximum(sil, (disk | hubb) * 1.0)

    shade = np.array(cfg["shade"])
    for ch in range(3):
        img[:, :, ch] = img[:, :, ch] * (1 - sil * 0.75) + shade[ch] * sil * 0.75

    out = np.clip(img, 0, 255).astype(np.uint8)[::-1]   # D3D+boxUVの向きに合わせ上下反転
    Image.fromarray(out, "RGB").save(
        rf"C:\Users\ryuto\Documents\TimeArrow\assets\textures\bg_sky{n}.png")
    print(f"bg_sky{n}.png written")


for n, cfg in SKIES.items():
    make_sky(n, cfg)
