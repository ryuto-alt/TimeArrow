"""ステージの総当たりテストプレイ.

no_arrow_search(): 矢を1本も使わずにゴールへ到達できる入力が存在するか、
制限時間内の全入力空間を幅優先で探索する。ここで到達できてしまうステージは
「矢を撃たなくてもクリアできる」=パズルとして成立していない。

全ステージのボタンは standOn=false(矢でしか押せない)なので、矢を使わない限り
ギミックの動きは時刻だけの関数になる。先に1回だけギミックを空回しして
毎フレームの位置を焼いておき、探索中はプレイヤーの物理だけを回す。
"""

from __future__ import annotations

import math
from collections import deque

from timearrow_sim import DT, Button, Inputs, World, load, overlap

HOLD = 6  # 1手 = 6フレーム(0.1秒)入力を保持する


def precompute(stage: str, seconds: float, fire=None, fire_frame=60):
    """プレイヤー不在でギミックを空回しし、毎フレームの位置/サイズを焼く。

    fire にターゲット名を渡すと、その1本だけを fire_frame で撃った world になる
    (矢1本ショートカットの検証用)。
    """
    w = load(stage)
    n = int(seconds / DT) + 2
    w.player.x, w.player.y = -1000.0, 1000.0  # 死亡判定に引っかからない場所へ退避
    frames = []
    snap = lambda: ({k: (v[0], v[1]) for k, v in w.pos.items()},
                    {k: (v[0] * 0.5, v[1] * 0.5) for k, v in w.scale.items()})
    frames.append(snap())
    for i in range(n):
        if fire and i == fire_frame:
            g = w.gizmos.get(fire)
            if isinstance(g, Button):
                g.press()
            elif g:
                g.skip(w.pp["maxSkip"])
        for name in w.order:
            w.gizmos[name].update(DT)
        frames.append(snap())
    return w, frames


class Runner:
    """焼いたフレーム列に対してプレイヤーの物理だけを回す(Player.lua と同一)。"""

    def __init__(self, w: World, frames):
        self.w = w
        self.frames = frames
        self.solids = w.solids
        self.stands = w.stands
        self.climbs = w.climbs
        self.hw, self.hh = w.half_w, w.half_h
        self.speed = w.pp["speed"]
        self.jump = w.pp["jumpSpeed"]
        self.grav = w.pp["gravity"]
        self.climb_speed = w.pp["climbSpeed"]
        self.kill_y = w.pp["killY"]
        self.pshw, self.pshh = w.ps[0] * 0.5, w.ps[1] * 0.5
        self.exit_name = w.exit_name
        self.exit_r = w.exit_props["radius"]
        # 触れると死ぬもの
        self.deadly = []
        for name, g in w.gizmos.items():
            if g.p.get("deadly"):
                hs = g.p.get("hitScale", 0.8)
                self.deadly.append((name, hs))
            if g.script == "RollBall.lua":
                self.deadly.append((name, g.p.get("hitScale", 0.8)))

    def col(self, fi, name):
        pos, sc = self.frames[fi]
        p = pos.get(name)
        if p is None or p[1] < -50:
            return None
        s = sc[name]
        return p[0], p[1], s[0], s[1]

    def step(self, st, fi, move, jump, vert):
        """st = (x, y, vy, grounded, ride). fi = 参照するギミックフレーム番号。"""
        x, y, vy, grounded, ride = st
        # 乗っている足場の移動分を運ぶ(前フレーム→今フレーム)
        if ride:
            a, b = self.col(fi - 1, ride), self.col(fi, ride)
            if a and b:
                x += b[0] - a[0]
                y += b[1] - a[1]
            else:
                ride = None

        # 地形へのめり込みを押し出す(壁の下で床に持ち上げられてすり抜けるのを防ぐ)
        for name in self.solids:
            c = self.col(fi, name)
            if not c:
                continue
            ex, ey, ehw, ehh = c
            ox = (self.hw + ehw) - abs(x - ex)
            oy = (self.hh + ehh) - abs(y - ey)
            if ox > 0.0001 and oy > 0.0001:
                if oy <= ox:
                    y = y + oy if y > ey else y - oy
                    if vy > 0:
                        vy = 0.0
                else:
                    x = x + ox if x > ex else x - ox

        vx = move * self.speed
        if grounded and jump:
            vy = self.jump
            grounded = False

        climbing = False
        if vert:
            for name in self.climbs:
                c = self.col(fi, name)
                if c and abs(x - c[0]) <= c[2] + 0.3 and abs(y - c[1]) <= c[3] + self.hh * 0.6:
                    climbing = True
                    break
        if climbing:
            vx, vy = 0.0, vert * self.climb_speed
        else:
            vy -= self.grav * DT

        px, py = x, y
        nx = px + vx * DT
        # --- X解決
        for name in self.solids:
            c = self.col(fi, name)
            if not c:
                continue
            ex, ey, ehw, ehh = c
            if abs(py - ey) >= (self.hh + ehh - 0.06):
                continue
            if abs(nx - ex) < (self.hw + ehw):
                if abs(px - ex) < (self.hw + ehw):
                    if abs(nx - ex) <= abs(px - ex):
                        nx = px
                else:
                    nx = (ex + ehw + self.hw) if nx > ex else (ex - ehw - self.hw)
        ny = py + vy * DT
        # --- Y解決
        if climbing:
            grounded, ride = False, None
        else:
            top_hit, top_name = None, None
            foot_prev, foot_new = py - self.hh, ny - self.hh
            head_prev, head_new = py + self.hh, ny + self.hh
            names = self.solids + (self.stands if vy <= 0 else [])
            for i, name in enumerate(names):
                one_way = i >= len(self.solids)
                c = self.col(fi, name)
                if not c:
                    continue
                ex, ey, ehw, ehh = c
                if abs(nx - ex) >= (self.hw + ehw):
                    continue
                top = ey + ehh
                if vy <= 0 and foot_prev >= top - 0.001 and foot_new <= top:
                    if top_hit is None or top > top_hit:
                        top_hit, top_name = top, name
                if not one_way:
                    bot = ey - ehh
                    if head_prev <= bot + 0.001 and head_new >= bot:
                        ny = bot - self.hh
                        if vy > 0:
                            vy = 0.0
            if top_hit is not None:
                ny, vy, grounded, ride = top_hit + self.hh, 0.0, True, top_name
            else:
                grounded, ride = False, None
        return (nx, ny, vy, grounded, ride)

    def dead(self, st, fi):
        x, y = st[0], st[1]
        if y < self.kill_y:
            return True
        pos, sc = self.frames[fi]
        for name, hs in self.deadly:
            p, s = pos.get(name), sc.get(name)
            if not p or p[1] < -50:
                continue
            if overlap(p[0], p[1], s[0] * hs, s[1] * hs, x, y, self.pshw, self.pshh):
                return True
        return False

    def at_goal(self, st, fi):
        c = self.col(fi, self.exit_name)
        if not c:
            return False
        return (c[0] - st[0]) ** 2 + (c[1] - st[1]) ** 2 < self.exit_r ** 2


def no_arrow_search(stage: str, beam=6000, verbose=True):
    """矢なしでクリアできる入力列を探す。見つかれば (True, 手順) を返す。"""
    w, frames = precompute(stage, load(stage).T + 0.5)
    r = Runner(w, frames)
    total_frames = int(w.T / DT)
    p0 = w.pos["Player"]
    start = (p0[0], p0[1], 0.0, False, None)
    has_climb = bool(w.climbs)

    actions = []
    for move in (-1, 0, 1):
        for jump in (False, True):
            actions.append((move, jump, 0))
    if has_climb:
        for move in (-1, 0, 1):
            for vert in (-1, 1):
                actions.append((move, False, vert))

    layer = {(round(start[0], 2), round(start[1], 2), 0.0, False, None): (start, [])}
    fi = 0
    steps = 0
    while fi < total_frames:
        nxt = {}
        for st, path in layer.values():
            for (move, jump, vert) in actions:
                s = st
                f = fi
                ok = True
                for k in range(HOLD):
                    if f + 1 > total_frames:
                        break
                    f += 1
                    s = r.step(s, f, move, jump and k == 0, vert)
                    steps += 1
                    if r.dead(s, f):
                        ok = False
                        break
                    if r.at_goal(s, f):
                        return True, path + [(move, jump, vert)], f * DT
                if not ok:
                    continue
                key = (round(s[0], 1), round(s[1], 1), round(s[2] * 2) / 2, s[3], s[4])
                if key not in nxt:
                    nxt[key] = (s, path + [(move, jump, vert)])
        if not nxt:
            break
        if len(nxt) > beam:
            # ゴールに近い順に残す
            gx = w.pos[w.exit_name][0]
            items = sorted(nxt.items(), key=lambda kv: abs(kv[1][0][0] - gx))[:beam]
            nxt = dict(items)
        layer = nxt
        fi += HOLD
    if verbose:
        print(f"  探索: {steps:,} フレーム評価 / 最終層 {len(layer)} 状態")
    return False, None, None


def explore(stage: str, beam=6000):
    """矢なしで到達できる状態を全部列挙する。

    返り値: (ゴール到達したか, 到達可能な (x,y) の集合, 到達可能な最大X)
    """
    w, frames = precompute(stage, load(stage).T + 0.5)
    r = Runner(w, frames)
    total_frames = int(w.T / DT)
    p0 = w.pos["Player"]
    start = (p0[0], p0[1], 0.0, False, None)

    actions = [(m, j, 0) for m in (-1, 0, 1) for j in (False, True)]
    if w.climbs:
        actions += [(m, False, v) for m in (-1, 0, 1) for v in (-1, 1)]

    reachable = set()
    layer = {(round(start[0], 1), round(start[1], 1), 0.0, False, None): start}
    fi = 0
    goal = False
    while fi < total_frames:
        nxt = {}
        for st in layer.values():
            for (move, jump, vert) in actions:
                s, f, ok = st, fi, True
                for k in range(HOLD):
                    if f + 1 > total_frames:
                        break
                    f += 1
                    s = r.step(s, f, move, jump and k == 0, vert)
                    if r.dead(s, f):
                        ok = False
                        break
                    reachable.add((round(s[0], 1), round(s[1], 1)))
                    if r.at_goal(s, f):
                        goal = True
                if not ok:
                    continue
                key = (round(s[0], 1), round(s[1], 1), round(s[2] * 2) / 2, s[3], s[4])
                if key not in nxt:
                    nxt[key] = s
        if not nxt:
            break
        if len(nxt) > beam:
            gx = w.pos[w.exit_name][0]
            nxt = dict(sorted(nxt.items(), key=lambda kv: abs(kv[1][0] - gx))[:beam])
        layer = nxt
        fi += HOLD
    return goal, reachable, (max(p[0] for p in reachable) if reachable else p0[0])


def shot_scan(stage: str, reachable, frame_idx=0, deg_step=1.0):
    """到達可能な各点から全方向へ矢を飛ばし、最初に当たるターゲットを集計する。

    矢は solids を貫通し、targets と arrowStops(地形)にだけ当たる。地形が遮蔽物になる。
    「登らなくても押せてしまうボタン」をここで機械的にあぶり出す。
    """
    w, frames = precompute(stage, load(stage).T + 0.5)
    pos, sc = frames[frame_idx]
    ah = w.pp["arrowHalf"]
    rng = w.pp["arrowRange"]
    step = w.pp["arrowSpeed"] * DT

    boxes = []
    for name in w.targets:
        p = pos.get(name)
        if p and p[1] > -50:
            boxes.append((name, True, p[0], p[1], sc[name][0], sc[name][1]))
    for name in w.stops:
        p = pos.get(name)
        if p and p[1] > -50:
            boxes.append((name, False, p[0], p[1], sc[name][0], sc[name][1]))

    hits = {}
    n_deg = int(360 / deg_step)
    for (px, py) in reachable:
        for d in range(n_deg):
            a = math.radians(d * deg_step)
            ax, ay = math.cos(a), math.sin(a)
            x, y = px + ax * 0.7, py + 0.2 + ay * 0.3
            travelled = 0.0
            while travelled < rng:
                x += ax * step
                y += ay * step
                travelled += step
                hit = None
                for (name, is_target, ex, ey, ehw, ehh) in boxes:
                    if overlap(x, y, ah, ah, ex, ey, ehw, ehh):
                        hit = (name, is_target)
                        break
                if hit:
                    if hit[1]:
                        hits.setdefault(hit[0], []).append((round(px, 1), round(py, 1), d * deg_step))
                    break
    return hits


def replay(stage: str, timeline, verbose=True):
    """(時刻, Inputs) のタイムラインを再生して結果を返す。意図した解法の検証用。"""
    w = load(stage)
    total = int(w.T / DT)
    events = sorted(timeline, key=lambda e: e[0])
    cur = Inputs()
    ei = 0
    log = []
    for i in range(total):
        t = i * DT
        jump_now = False
        while ei < len(events) and events[ei][0] <= t + 1e-9:
            new = events[ei][1]
            jump_now = new.jump
            cur = Inputs(move=new.move, jump=False, vert=new.vert, draw=new.draw, aim=new.aim)
            ei += 1
        cleared, death = w.step(Inputs(cur.move, jump_now, cur.vert, cur.draw, cur.aim))
        if verbose and i % 30 == 0:
            log.append(f"    t={t:4.1f} x={w.player.x:5.2f} y={w.player.y:5.2f} "
                       f"arrow={'飛' if w.player.arrow_flying else ('刺' if w.player.arrow_stuck else '手')}")
        if death:
            return {"result": "死亡", "why": death, "t": t, "log": log}
        if cleared:
            return {"result": "クリア", "t": round(t, 2), "log": log,
                    "x": w.player.x, "y": w.player.y}
    return {"result": "タイムアップ", "t": w.T, "log": log,
            "x": round(w.player.x, 2), "y": round(w.player.y, 2)}


def one_shot_search(stage: str, beam=6000):
    """「どれか1つのターゲットを1回撃つだけ」でクリアできてしまわないか調べる。

    2射以上を要求する設計のステージで、1射ショートカットが残っていないかの検証。
    返り値: 抜け道になったターゲット名のリスト。
    """
    base = load(stage)
    bad = []
    for target in base.targets:
        w, frames = precompute(stage, base.T + 0.5, fire=target)
        r = Runner(w, frames)
        total = int(w.T / DT)
        p0 = w.pos["Player"]
        start = (p0[0], p0[1], 0.0, False, None)
        actions = [(m, j, 0) for m in (-1, 0, 1) for j in (False, True)]
        if w.climbs:
            actions += [(m, False, v) for m in (-1, 0, 1) for v in (-1, 1)]
        layer = {(round(start[0], 1), round(start[1], 1), 0.0, False, None): start}
        fi = 0
        while fi < total:
            nxt = {}
            for st in layer.values():
                for (move, jump, vert) in actions:
                    s, f, ok = st, fi, True
                    for k in range(HOLD):
                        if f + 1 > total:
                            break
                        f += 1
                        s = r.step(s, f, move, jump and k == 0, vert)
                        if r.dead(s, f):
                            ok = False
                            break
                        if r.at_goal(s, f):
                            bad.append(target)
                            ok = False
                            fi = total
                            break
                    if not ok:
                        continue
                    key = (round(s[0], 1), round(s[1], 1), round(s[2] * 2) / 2, s[3], s[4])
                    nxt.setdefault(key, s)
            if target in bad or not nxt:
                break
            if len(nxt) > beam:
                gx = w.pos[w.exit_name][0]
                nxt = dict(sorted(nxt.items(), key=lambda kv: abs(kv[1][0] - gx))[:beam])
            layer = nxt
            fi += HOLD
    return bad
