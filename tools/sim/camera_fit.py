"""ステージカメラの画角を逆算して、全体が確実に収まる位置を求める.

エンジンのカメラ規約(src/core/Application.cpp):
  forward.y = sin(radians(-rotation.x))  → rotation.x=+28 は「下向き28度」
  投影は XMMatrixPerspectiveFovLH(fovDegrees=垂直FOV, aspect=1280/720)

下向きに傾いたカメラで z=0 の平面を見ると、画面下端は遠くまで届き上端は近い
=上下非対称になる。中央合わせで置くと上が切れる/下に虚無が広がるので、
上端と下端が同時にコンテンツに接するように距離と高さを解く。
"""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENES = ROOT / "assets" / "scenes"

ASPECT = 1280.0 / 720.0
FOV_DEG = 50.0

# 背景・演出用で、画角合わせの対象にしないもの
IGNORE = {"Backdrop", "Sun", "Grid", "GameCamera", "Arrow", "GameManager", "DirLight"}

TALL = 4.5   # これより高い壁は上端を切って画角合わせから外す


def visible_range(cam_y, cam_z, pitch_deg, fov_deg=FOV_DEG, aspect=ASPECT):
    """z=0 の平面上で画面に映る Y 範囲と、画面上端での X 半幅を返す。"""
    th = math.radians(pitch_deg)
    c, s = math.cos(th), math.sin(th)
    T = math.tan(math.radians(fov_deg) / 2)
    tanH = T * aspect
    D = -cam_z                      # カメラから z=0 平面までの奥行き
    L = D / c                       # 視線方向の距離
    up = L * T / (c + T * s)        # 上へ届く量
    dn = L * T / (c - T * s)        # 下へ届く量(こちらが大きい)
    y_center = cam_y - L * s
    x_half_top = tanH * L * c / (c + T * s)
    return y_center - dn, y_center + up, x_half_top


def fit(x0, x1, y0, y1, pitch_deg, fov_deg=FOV_DEG, aspect=ASPECT, margin_bottom=0.8):
    """箱 [x0,x1]x[y0,y1] が収まるカメラ (x, y, z) を解く。

    16マス幅 × 6マス前後のステージを 16:9 に収めると縦は必ず余る。その余りを
    上下に均等配分すると床の下の虚無が画面の半分を占めるので、下の余白は
    margin_bottom で固定し、余りは全部「空」の側(上)へ逃がす。
    """
    th = math.radians(pitch_deg)
    c, s = math.cos(th), math.sin(th)
    T = math.tan(math.radians(fov_deg) / 2)
    tanH = T * aspect

    up_k = T / (c + T * s)          # 上へ届く量 = L * up_k
    dn_k = T / (c - T * s)          # 下へ届く量 = L * dn_k

    # 縦: 下端を y0-margin_bottom に置いたまま上端が y1 に届く距離
    L = (y1 - y0 + margin_bottom) / (up_k + dn_k)
    # 横: 画面上端(いちばん狭い行)でも x0..x1 が入る距離
    cx = (x0 + x1) / 2
    need_half = max(cx - x0, x1 - cx)
    L_h = need_half * (c + T * s) / (tanH * c)
    L = max(L, L_h)

    # 下端を y0-margin_bottom に固定して逆算(余りは上へ)
    y_center = (y0 - margin_bottom) + L * dn_k
    cam_y = y_center + L * s
    cam_z = -L * c
    return cx, cam_y, cam_z, L


def content_box(stage_or_entities):
    """ステージの見せたい範囲。動く床は振れ幅、隠れている足場は出現後の位置で見る。"""
    if isinstance(stage_or_entities, str):
        ents = json.loads(
            (SCENES / f"{stage_or_entities}.json").read_text(encoding="utf-8"))["entities"]
    else:
        ents = stage_or_entities
    x0 = y0 = 1e9
    x1 = y1 = -1e9
    for e in ents:
        n = e["name"]
        if n in IGNORE or "transform" not in e:
            continue
        if any(k.startswith("ui") for k in e) or "parent" in e:
            continue
        p = e["transform"]["position"]
        sc = e["transform"]["scale"]
        hw, hh = abs(sc[0]) / 2, abs(sc[1]) / 2
        ax0, ax1 = p[0] - hw, p[0] + hw
        ay0, ay1 = p[1] - hh, p[1] + hh
        # 高い壁/柱は「画面外へ伸びている」で読めるので、全高を映す必要はない。
        # これを入れるとカメラが極端に引いてステージ本体が小さくなる
        if (ay1 - ay0) > TALL:
            ay1 = ay0 + TALL
        ls = e.get("luaScript")
        if ls:
            sp = Path(ls["scriptPath"]).name
            pr = {q["name"]: q["value"] for q in ls.get("props", [])}
            if sp == "MovingPlatform.lua":       # 上下に振れる
                ay0 -= pr.get("amplitude", 0)
                ay1 += pr.get("amplitude", 0)
            elif sp == "Pendulum.lua":           # 左右に振れる
                ax0 -= pr.get("amplitude", 0)
                ax1 += pr.get("amplitude", 0)
            elif sp == "CrushWall.lua":          # 走り抜ける範囲まで
                t = pr.get("travel", 0) * pr.get("axisX", -1)
                ax0, ax1 = min(ax0, ax0 + t), max(ax1, ax1 + t)
            elif sp == "TimedDoor.lua":          # 沈む先は見えなくてよい
                pass
        x0, x1 = min(x0, ax0), max(x1, ax1)
        y0, y1 = min(y0, ay0), max(y1, ay1)
    return x0, x1, y0, y1


def report(stage: str, pitch=None, margin_x=0.6, margin_y=0.5):
    d = json.loads((SCENES / f"{stage}.json").read_text(encoding="utf-8"))
    cam = next(e for e in d["entities"] if e["name"] == "GameCamera")
    cp = cam["transform"]["position"]
    cur_pitch = cam["transform"]["rotation"][0]
    pitch = cur_pitch if pitch is None else pitch

    bx0, bx1, by0, by1 = content_box(stage)
    vy0, vy1, vxh = visible_range(cp[1], cp[2], cur_pitch)
    cut = []
    if by1 > vy1:
        cut.append(f"上が {by1 - vy1:.2f} 見切れ")
    if by0 < vy0:
        cut.append(f"下が {vy0 - by0:.2f} 見切れ")
    if bx1 > cp[0] + vxh:
        cut.append(f"右が {bx1 - cp[0] - vxh:.2f} 見切れ")
    if bx0 < cp[0] - vxh:
        cut.append(f"左が {cp[0] - vxh - bx0:.2f} 見切れ")
    waste = (vy1 - vy0) / (by1 - by0)

    nx, ny, nz, L = fit(bx0 - margin_x, bx1 + margin_x, by0 - margin_y, by1 + margin_y, pitch)
    return {
        "内容": (round(bx0, 2), round(bx1, 2), round(by0, 2), round(by1, 2)),
        "現在の可視Y": (round(vy0, 2), round(vy1, 2)),
        "現在の可視X": (round(cp[0] - vxh, 2), round(cp[0] + vxh, 2)),
        "問題": " / ".join(cut) if cut else "見切れなし",
        "縦の無駄": f"{waste:.2f}倍",
        "推奨": (round(nx, 2), round(ny, 2), round(nz, 2)),
        "pitch": pitch,
    }


if __name__ == "__main__":
    print("俯角ごとの比較(数字は 画面の縦 ÷ 内容の高さ。1に近いほど画面を使えている)")
    print(f"{'':10s}" + "".join(f"{p:>10}°" for p in (28, 20, 14, 8)))
    for s in ["stage1", "stage2", "stage3", "stage4", "stage5"]:
        bx0, bx1, by0, by1 = content_box(s)
        row = []
        for pitch in (28, 20, 14, 8):
            _, cy, cz, _ = fit(bx0 - 0.5, bx1 + 0.5, by0, by1 + 0.5, pitch)
            v0, v1, _ = visible_range(cy, cz, pitch)
            row.append((v1 - v0) / (by1 - by0))
        print(f"{s:10s}" + "".join(f"{v:>10.2f} " for v in row))


PITCH = 14.0          # 俯角。28度は下端が y=-12 まで届いて画面の大半が虚無になっていた
MARGIN_X = 0.5
MARGIN_TOP = 0.5
MARGIN_BOTTOM = 0.8


def camera_for(entities, extra_top=0.0):
    """エンティティ配列から、全体が収まるカメラ position を返す。"""
    bx0, bx1, by0, by1 = content_box(entities)
    cx, cy, cz, _ = fit(bx0 - MARGIN_X, bx1 + MARGIN_X, by0, by1 + MARGIN_TOP + extra_top,
                        PITCH, margin_bottom=MARGIN_BOTTOM)
    return [round(cx, 2), round(cy, 2), round(cz, 2)], PITCH


def check(stage: str):
    """書き出し済みシーンで見切れが無いか検算する。"""
    d = json.loads((SCENES / f"{stage}.json").read_text(encoding="utf-8"))
    cam = next(e for e in d["entities"] if e["name"] == "GameCamera")
    cp = cam["transform"]["position"]
    pitch = cam["transform"]["rotation"][0]
    bx0, bx1, by0, by1 = content_box(d["entities"])
    vy0, vy1, vxh = visible_range(cp[1], cp[2], pitch)
    cut = []
    if by1 > vy1: cut.append(f"上{by1 - vy1:.2f}")
    if by0 < vy0: cut.append(f"下{vy0 - by0:.2f}")
    if bx1 > cp[0] + vxh: cut.append(f"右{bx1 - cp[0] - vxh:.2f}")
    if bx0 < cp[0] - vxh: cut.append(f"左{cp[0] - vxh - bx0:.2f}")
    return {
        "見切れ": " ".join(cut) if cut else "なし",
        "可視Y": (round(vy0, 2), round(vy1, 2)),
        "可視X": (round(cp[0] - vxh, 2), round(cp[0] + vxh, 2)),
        "内容Y": (round(by0, 2), round(by1, 2)),
        "床下の虚無": round(by0 - vy0, 2),
        "縦の使用率": round((by1 - by0) / (vy1 - vy0), 2),
    }


def backdrop_for(cam_pos, pitch_deg, bz, margin=1.06, fov_deg=FOV_DEG, aspect=ASPECT):
    """奥の壁(Backdrop)を、その奥行きでの画角いっぱいに広げるための (position, scale) を返す。

    壁が画面より小さいと縁が見えてしまい、床より下も素通しの空になる。画角に合わせると
    床下の余白も壁で埋まり、崩壊エフェクトも画面全体に効く。
    """
    cx, cy, cz = cam_pos
    th = math.radians(pitch_deg)
    c, s = math.cos(th), math.sin(th)
    T = math.tan(math.radians(fov_deg) / 2)
    tanH = T * aspect
    D = bz - cz
    t_top, t_bot = D / (c + T * s), D / (c - T * s)
    y_top = cy + t_top * (-s + T * c)
    y_bot = cy + t_bot * (-s - T * c)
    half_w = tanH * t_bot          # いちばん広い行(画面下端)に合わせる
    w = 2 * half_w * margin
    h = (y_top - y_bot) * margin
    return [round(cx, 2), round((y_top + y_bot) / 2, 2), bz], [round(w, 2), round(h, 2), 1.0]
