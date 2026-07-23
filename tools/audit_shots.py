# -*- coding: utf-8 -*-
"""射線監査 — 「ここからは撃てないはず」を機械で証明する。

TimeArrowには「特定の場所からしか撃てない的」でパズルを組んでいる箇所がある:
  S7 Button1  デッキからのみ(地上から撃てたら大回廊を丸ごと飛ばせる)
  S6 Bomb62   レッジからのみ(地上から撃てたら順序制約が消える)
これが地形の微調整で崩れるのを防ぐ。実際、S7の谷を[10,16]→[12,16.5]へ動かした際、
橋の着地点(x=15.5〜16.5)から真上に撃つとButton1に届くようになっていた(検出→塔を拡幅して修正)。

矢のモデルは Player.lua に一致させる:
  直線飛翔 / 射程18 / arrowStops に当たったら手前で停止 /
  的の判定は最低でも半幅・半高0.8を保証 / 照準は10度刻み。
"""
import json, os, sys, math

SCENES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "scenes")
RANGE, AH, STEP = 18.0, 0.1, 0.05

# (stage, 的, 禁止射点の説明, [(x0, x1, y)]) — この帯から撃って当たったらNG
FORBIDDEN = [
    (7, "Button1", "地上(デッキからのみ撃てるはず)", [(1.0, 46.0, 0.55)]),
    (6, "Bomb62", "地上(レッジ上からのみ撃てるはず)", [(20.5, 64.0, 0.55)]),
]
# (stage, 的, 意図した射点の説明, [(x0, x1, y)]) — ここからは当たらないとパズルが解けない
REQUIRED = [
    (7, "Button1", "デッキ西端", [(18.0, 24.0, 4.95)]),
    (6, "Bomb62", "レッジ上(爆風圏外)", [(40.0, 42.0, 4.95)]),
]


def load(n):
    with open(os.path.join(SCENES, f"stage{n}.json"), encoding="utf-8") as f:
        return json.load(f)


def setup(n, target):
    sc = load(n)
    ent = {e["name"]: e for e in sc["entities"]}
    props = {q["name"]: q["value"] for q in ent["Player"]["luaScript"]["props"]}
    boxes = []
    for nm in [s.strip() for s in props["arrowStops"].split(",") if s.strip()]:
        e = ent[nm]
        p, s = e["transform"]["position"], e["transform"]["scale"]
        if p[1] < -50:
            continue
        boxes.append((p[0] - s[0] / 2, p[0] + s[0] / 2, p[1] - s[1] / 2, p[1] + s[1] / 2))
    t = ent[target]["transform"]
    tgt = (t["position"][0], t["position"][1],
           max(t["scale"][0] / 2, 0.8), max(t["scale"][1] / 2, 0.8))
    return boxes, tgt


def shoot(boxes, tgt, x0, y0, ang):
    """(x0,y0) から ang 度に撃って的に当たるか。当たれば飛距離、当たらなければ None。"""
    bx, by, bhw, bhh = tgt
    dx, dy = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    t = 0.0
    while t < RANGE:
        t += STEP
        x, y = x0 + dx * t, y0 + dy * t
        if abs(x - bx) < bhw + AH and abs(y - by) < bhh + AH:
            return round(t, 1)
        for a0, a1, b0, b1 in boxes:
            if a0 - AH < x < a1 + AH and b0 - AH < y < b1 + AH:
                return None          # 地形に刺さった
    return None


def scan(boxes, tgt, bands):
    hits = []
    for x0, x1, y in bands:
        xi = x0
        while xi <= x1:
            for e in range(-90, 91, 10):                 # 10度刻み(Player.lua と同じ)
                for ang in (e, 180 - e):
                    d = shoot(boxes, tgt, xi, y, ang)
                    if d is not None:
                        hits.append((round(xi, 1), ang, d))
            xi += 0.1
    return hits


FORBIDDEN = [c for c in FORBIDDEN if c[0] <= 4]   # stage4まで構成
REQUIRED  = [c for c in REQUIRED  if c[0] <= 4]
NG = []
print("=== 射線監査: 撃てては困る場所から撃てないこと ===")
for n, target, desc, bands in FORBIDDEN:
    boxes, tgt = setup(n, target)
    hits = scan(boxes, tgt, bands)
    if hits:
        NG.append((n, target))
        xs = sorted({h[0] for h in hits})
        print(f" stage{n} {target}: ✗ {desc} から {len(hits)}通り命中"
              f" (射点 x={xs[0]:.1f}〜{xs[-1]:.1f}, 例 {hits[0][1]}度)")
    else:
        print(f" stage{n} {target}: OK ({desc} からは当たらない)")

print("\n=== 射線監査: 意図した場所からは必ず撃てること ===")
for n, target, desc, bands in REQUIRED:
    boxes, tgt = setup(n, target)
    hits = scan(boxes, tgt, bands)
    if hits:
        print(f" stage{n} {target}: OK ({desc} から {len(hits)}通り命中)")
    else:
        NG.append((n, target))
        print(f" stage{n} {target}: ✗ {desc} からも当たらない = 解けない")

print("\n判定:", "ALL OK — 射線パズルは成立している" if not NG else f"NG: {NG}")
sys.exit(1 if NG else 0)
