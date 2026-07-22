# -*- coding: utf-8 -*-
"""抜け道監査 — 「歩くだけでどこまで行けるか」を機械で出す。

旧S6で見つかったバグ(レッジ下の地上が素通しで、爆弾2枚と門を丸ごとスキップできた)と
同じ型の抜け道を全ステージで潰すためのツール。sim_stages.py が「時間の収支」を証明するのに対し、
こちらは「地形が意図した経路を強制しているか」を証明する。

監査1: プレイヤー開始位置から、ギミックを一切使わず歩いて出口に届かないこと。
監査2: 門/格子/動く壁/砲台/爆破可能な瓦礫を全部「開いている」ものとみなし、さらに
       各地上ブロックの左端(=谷を渡り終えた地点)からも歩かせる。それでも出口に
       届かないこと。届いたなら、間に挟まっている上層のギミックを丸ごと飛ばせる。

移動モデルは設計値: 歩く / 段差1.35まで登る / 隙間2.0まで飛ぶ。
"""
import json, os, sys

SCENES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "scenes")

STEP_UP = 1.35        # 登れる段差の上限(設計値)
JUMP_GAP = 2.0        # 飛び越せる隙間の上限(設計値。物理限界2.9に余裕)
HALF_W = 0.34         # プレイヤー半幅
SCAN = 0.1            # x方向の走査刻み

# いずれ通れるようになる障害物 = 監査2では「無い物」として扱う
SOFT_SCRIPTS = ("TimedDoor.lua", "Lattice.lua", "CrushWall.lua", "Turret.lua")


def load(n):
    with open(os.path.join(SCENES, f"stage{n}.json"), encoding="utf-8") as f:
        return json.load(f)


def player_props(scene):
    pl = next(e for e in scene["entities"] if e["name"] == "Player")
    return pl["transform"]["position"], {q["name"]: q["value"] for q in pl["luaScript"]["props"]}


def solid_names(scene):
    _, props = player_props(scene)
    return {s.strip() for s in props["solids"].split(",") if s.strip()}


def soft_names(scene):
    out = set()
    for e in scene["entities"]:
        lua = e.get("luaScript", {}).get("scriptPath", "")
        if any(lua.endswith(x) for x in SOFT_SCRIPTS):
            out.add(e["name"])
        elif lua.endswith("Wall.lua"):
            props = {q["name"]: q["value"] for q in e["luaScript"]["props"]}
            if not props.get("deadly", False):      # 爆破可能な瓦礫(トゲではない)
                out.add(e["name"])
    return out


def aabbs(scene, names):
    """(x0, x1, ytop, ybot)。y=-100 の退避プールは除外。"""
    out = []
    for e in scene["entities"]:
        if e["name"] not in names:
            continue
        p, s = e["transform"]["position"], e["transform"]["scale"]
        if p[1] < -50:
            continue
        out.append((p[0] - s[0] / 2, p[0] + s[0] / 2, p[1] + s[1] / 2, p[1] - s[1] / 2))
    return out


def floor_at(bxs, x, max_y=None):
    """x で立てる面の高さ。max_y を渡すと「そこまでしか登れない」= 上の層は
    天井として無視され、その下をくぐる挙動になる(旧S6のバグを再現できる)。"""
    best = None
    for x0, x1, ytop, _ in bxs:
        if x0 - HALF_W < x < x1 + HALF_W:
            if max_y is not None and ytop > max_y:
                continue
            if best is None or ytop > best:
                best = ytop
    return best


def blocked(bxs, x, y):
    """足元 y に立っているとき、x で胴体(y+0.15〜y+1.0)が塞がれているか。"""
    for x0, x1, ytop, ybot in bxs:
        if x0 - HALF_W < x < x1 + HALF_W and ybot < y + 1.0 and ytop > y + 0.15:
            return True
    return False


def walk(bxs, start_x):
    """start_x から右へ歩けるところまで歩く。(到達x, その高さ, 止まった理由)"""
    x = start_x
    y = floor_at(bxs, x)
    if y is None:
        return x, 0.0, "床が無い"
    while x < 200:
        nx = x + SCAN
        f = floor_at(bxs, nx, max_y=y + STEP_UP)      # 上の層はくぐる(登らない)
        if f is None or f < y - 8.0:                  # 奈落: 飛び越せるか
            jx, landed = nx, False
            while jx < nx + JUMP_GAP:
                jx += SCAN
                g = floor_at(bxs, jx, max_y=y + STEP_UP)
                if g is not None and g > y - 8.0:
                    nx, f, landed = jx, g, True
                    break
            if not landed:
                return x, y, f"奈落(隙間>{JUMP_GAP}u)"
        if blocked(bxs, nx, f):
            return x, y, "壁/門で通行不可"
        x, y = nx, f
    return x, y, "上限"


def exit_pos(scene):
    e = next(x for x in scene["entities"] if x["name"] == "Exit")
    return e["transform"]["position"][0], e["transform"]["position"][1]


def reached_exit(x, y, gx, gy):
    return x > gx - 1.2 and abs(y + 0.55 - gy) < 1.2


FAIL, SKIP = [], []

print("=== 監査1: 開始位置からギミック無しで歩ける範囲 ===")
for n in range(1, 9):
    sc = load(n)
    bxs = aabbs(sc, solid_names(sc))
    gx, gy = exit_pos(sc)
    x, y, why = walk(bxs, player_props(sc)[0][0])
    bad = reached_exit(x, y, gx, gy)
    print(f" stage{n}: x={x:6.1f} y={y:5.2f} で停止 ({why}) / 出口({gx:.1f},{gy:.2f})"
          f"  {'✗ 徒歩だけで出口!!' if bad else 'OK'}")
    if bad:
        FAIL.append(n)

print("\n=== 監査2: 門/格子/動く壁/砲台/瓦礫を全開にし、各地上ブロックの左端からも歩く ===")
for n in range(1, 9):
    sc = load(n)
    names = solid_names(sc) - soft_names(sc)
    bxs = aabbs(sc, names)
    gx, gy = exit_pos(sc)
    seeds, decks = [player_props(sc)[0][0]], []
    for e in sc["entities"]:
        if e["name"] not in names:
            continue
        p, s = e["transform"]["position"], e["transform"]["scale"]
        ybot, ytop = p[1] - s[1] / 2, p[1] + s[1] / 2
        if s[0] >= 4.0 and abs(ytop) < 0.6:                   # 地上ブロック
            seeds.append(p[0] - s[0] / 2 + 0.5)
        elif s[0] >= 4.0 and ytop >= 3.0 and ybot >= 1.0:     # 上層の板
            decks.append((round(p[0] - s[0] / 2, 1), round(p[0] + s[0] / 2, 1)))
    hits = []
    for sx in sorted({round(v, 1) for v in seeds}):
        x, y, _ = walk(bxs, sx)
        if reached_exit(x, y, gx, gy):
            skipped = [d for d in decks if d[0] > sx and d[1] < gx]
            if skipped:
                hits.append((sx, skipped))
    if hits:
        SKIP.append(n)
        for sx, sk in hits:
            print(f" stage{n}: ✗ x={sx:.1f} から歩くだけで出口。飛ばせる上層={sk}")
    else:
        print(f" stage{n}: OK")

print("\n判定:", "ALL OK — どのステージも地形が意図した経路を強制している"
      if not FAIL and not SKIP else f"NG: 徒歩抜け道={FAIL} / 上層スキップ={SKIP}")
sys.exit(1 if (FAIL or SKIP) else 0)
