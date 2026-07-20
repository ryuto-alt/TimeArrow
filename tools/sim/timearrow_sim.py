"""TimeArrow ヘッドレスシミュレータ.

assets/scripts/*.lua の挙動を Python で1:1に再現し、エンジンを起動せずにステージを
テストプレイする。目的は2つ:
  1. 「矢を1本も使わずにクリアできてしまわないか」を総当たり探索で証明する
  2. 「意図した解法が制限時間10秒以内に通るか」を入力タイムラインの再生で確認する

物理は Player.lua と同じ順序・同じ式・同じ dt(1/60) で積分する。スクリプトの更新順は
シーンJSONのエンティティ順(=エンジンの更新順)に合わせてある。
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field, replace
from pathlib import Path

DT = 1.0 / 60.0

ROOT = Path(__file__).resolve().parents[2]
SCENES = ROOT / "assets" / "scenes"


def _props(node):
    out = {}
    for p in node.get("props", []):
        out[p["name"]] = p["value"]
    return out


def _split(csv):
    return [w.strip() for w in (csv or "").split(",") if w.strip()]


def overlap(ax, ay, ahw, ahh, bx, by, bhw, bhh):
    return abs(ax - bx) < (ahw + bhw) and abs(ay - by) < (ahh + bhh)


# --------------------------------------------------------------------------
# ギミック(Player以外のスクリプト)。共通で time_skip による早送りを受け取る
# --------------------------------------------------------------------------
class Gizmo:
    """1エンティティ分のスクリプト状態。位置は world.pos[name] に書き戻す。"""

    ff_duration = 0.5  # 早送りを消化する秒数(各Luaの既定)

    def __init__(self, world, name, script, props, pos, scale):
        self.w = world
        self.name = name
        self.script = script
        self.p = props
        self.bx, self.by, self.bz = pos
        self.scale = list(scale)
        self.clock = 0.0
        self.ff_remain = 0.0
        self.ff_speed = 0.0
        self.ghost_t = 0.0
        self.button_flag = None
        self.dead_flag = False

    def skip(self, amount):
        self.ff_remain += amount
        self.ff_speed = self.ff_remain / max(self.ff_duration, 0.05)

    def advance_clock(self, dt, run=True):
        if run:
            self.clock += dt
        if self.ff_remain > 0:
            step = min(self.ff_remain, self.ff_speed * dt)
            self.clock += step
            self.ff_remain -= step

    def update(self, dt):
        pass


class MovingPlatform(Gizmo):
    def update(self, dt):
        if self.clock == 0.0 and not hasattr(self, "_init"):
            self._init = True
            self.clock = float(self.p.get("startPhase", 0.0))
        self.advance_clock(dt)
        ang = math.sin((self.clock / self.p["period"]) * math.pi * 2)
        self.w.pos[self.name] = (self.bx, self.by + ang * self.p["amplitude"], self.bz)


class Pendulum(Gizmo):
    def update(self, dt):
        if not hasattr(self, "_init"):
            self._init = True
            self.clock = float(self.p.get("startPhase", 0.0))
        self.advance_clock(dt)
        ang = math.sin((self.clock / self.p["period"]) * math.pi * 2)
        nx = self.bx + ang * self.p["amplitude"]
        self.w.pos[self.name] = (nx, self.by, self.bz)
        if self.p.get("deadly") and self.ff_remain <= 0:
            hs = self.p.get("hitScale", 0.8)
            if self.w.hits_player(nx, self.by, self.scale[0] * 0.5 * hs, self.scale[1] * 0.5 * hs):
                self.w.kill("Pendulum:" + self.name)


class Wall(Gizmo):
    def update(self, dt):
        if not self.p.get("deadly"):
            return
        hs = self.p.get("hitScale", 0.8)
        if self.w.hits_player(self.bx, self.by, self.scale[0] * 0.5 * hs, self.scale[1] * 0.5 * hs):
            self.w.kill("Wall:" + self.name)


class CrushWall(Gizmo):
    ff_duration = None  # ghostTime を使う

    def __init__(self, *a):
        super().__init__(*a)
        self.button_active = bool(self.p.get("startActive", True))

    def skip(self, amount):
        self.ff_remain += amount
        gt = max(self.p.get("ghostTime", 0.35), 0.05)
        self.ff_speed = self.ff_remain / gt
        self.ghost_t = gt
        self.w.ghost[self.name] = gt

    def _pos_at(self, c):
        max_e = self.p["travel"] / self.p["speed"]
        e = max(0.0, min(c - self.p["startT"], max_e))
        return self.bx + self.p["axisX"] * self.p["speed"] * e

    def update(self, dt):
        run = (not self.p.get("listenButton")) or self.button_active
        self.advance_clock(dt, run)
        if self.ghost_t > 0:
            self.ghost_t -= dt
        self.w.pos[self.name] = (self._pos_at(self.clock), self.by, self.bz)


class TimedDoor(Gizmo):
    def __init__(self, *a):
        super().__init__(*a)
        self.button_open = False

    def update(self, dt):
        if self.p.get("listenButton"):
            is_open = self.button_open
        else:
            self.advance_clock(dt)
            is_open = self.p["openT"] <= self.clock < self.p["closeT"]
        y = self.by - self.p["sinkAmount"] if is_open else self.by
        self.w.pos[self.name] = (self.bx, y, self.bz)
        if is_open or not self.p.get("deadly") or self.ff_remain > 0:
            return
        hs = self.p.get("hitScale", 0.8)
        if self.w.hits_player(self.bx, self.by, self.scale[0] * 0.5 * hs, self.scale[1] * 0.5 * hs):
            self.w.kill("Door:" + self.name)


class RisePlatform(Gizmo):
    def __init__(self, *a):
        super().__init__(*a)
        self.button_up = False
        self.cur_frac = 0.0
        self.w.pos[self.name] = (self.bx, self.p.get("hideY", -100.0), self.bz)

    def update(self, dt):
        if self.p.get("listenButton"):
            target = 1.0 if self.button_up else 0.0
            step = dt / max(self.p.get("riseTime", 0.4), 0.05)
            self.cur_frac = min(target, self.cur_frac + step) if self.cur_frac < target \
                else max(target, self.cur_frac - step)
            frac = self.cur_frac
        else:
            self.advance_clock(dt)
            frac = max(0.0, min((self.clock - self.p["arriveT"]) / max(self.p["riseTime"], 1e-6), 1.0))
        hide = self.p.get("hideY", -100.0)
        self.w.pos[self.name] = (self.bx, hide + (self.by - hide) * frac, self.bz)


class GrowVine(Gizmo):
    def __init__(self, *a):
        super().__init__(*a)
        self.base = list(self.scale)
        self._apply(0.0)

    def _apply(self, frac):
        sy = max(0.04, frac) * self.base[1]
        self.scale = [self.base[0], sy, self.base[2]]
        self.w.scale[self.name] = list(self.scale)
        y = self.p.get("bottomY", 0.0) + (sy * self.p.get("unitHeight", 3.0)) * 0.5
        self.w.pos[self.name] = (self.bx, y, self.bz)

    def update(self, dt):
        self.advance_clock(dt)
        frac = max(0.0, min((self.clock - self.p["growT"]) / max(self.p["growDuration"], 1e-6), 1.0))
        self._apply(frac)


class RollBall(Gizmo):
    def __init__(self, *a):
        super().__init__(*a)
        self.broke = False
        self.passed = False

    def update(self, dt):
        self.advance_clock(dt)
        if self.passed:
            return
        elapsed = max(0.0, self.clock - self.p["rollT"])
        nx = self.bx + self.p["axisX"] * self.p["rollSpeed"] * elapsed
        self.w.pos[self.name] = (nx, self.by, self.bz)
        if self.ff_remain > 0:
            return
        gx, gy, _ = self.w.pos.get(self.p.get("goalName", "Exit"), (1e9, 0, 0))
        gs = self.w.scale.get(self.p.get("goalName", "Exit"), [1, 1, 1])
        ghs = self.p.get("goalHitScale", 1.3)
        s = self.w.scale[self.name]
        if not self.broke and overlap(nx, self.by, s[0] * 0.5, s[1] * 0.5,
                                      gx, gy, gs[0] * 0.5 * ghs, gs[1] * 0.5 * ghs):
            self.broke = True
            self.w.goal_broken = True
        hs = self.p.get("hitScale", 0.8)
        if self.w.hits_player(nx, self.by, s[0] * 0.5 * hs, s[1] * 0.5 * hs):
            self.w.kill("Ball:" + self.name)


class Button(Gizmo):
    def __init__(self, *a):
        super().__init__(*a)
        self.was_standing = False

    def press(self):
        link = self.p.get("linkTarget", "")
        if not link:
            return
        if self.p.get("skipAmount", 0.0) > 0:
            self.w.time_skip(link, self.p["skipAmount"])
        else:
            self.w.button_toggle(link)

    def on_arrow(self):
        if self.p.get("arrowHit", True):
            self.press()

    def update(self, dt):
        standing = False
        if self.p.get("standOn", True):
            s = self.w.scale[self.name]
            standing = self.w.hits_player(self.bx, self.by, s[0] * 0.5, s[1] * 0.5)
        if standing and not self.was_standing:
            self.press()
        self.was_standing = standing


SCRIPTS = {
    "MovingPlatform.lua": MovingPlatform,
    "Pendulum.lua": Pendulum,
    "Wall.lua": Wall,
    "CrushWall.lua": CrushWall,
    "TimedDoor.lua": TimedDoor,
    "RisePlatform.lua": RisePlatform,
    "GrowVine.lua": GrowVine,
    "RollBall.lua": RollBall,
    "Button.lua": Button,
}


# --------------------------------------------------------------------------
# プレイヤー(Player.lua の移動部を1:1で再現)
# --------------------------------------------------------------------------
@dataclass
class PlayerState:
    x: float
    y: float
    vx: float = 0.0
    vy: float = 0.0
    facing: int = 1
    grounded: bool = False
    climbing: bool = False
    ride: str | None = None
    ride_px: float = 0.0
    ride_py: float = 0.0
    has_arrow: bool = True
    arrow_flying: bool = False
    arrow_stuck: bool = False
    arrow_x: float = 0.0
    arrow_y: float = 0.0
    arrow_vx: float = 0.0
    arrow_vy: float = 0.0
    arrow_from: tuple = (0.0, 0.0)
    arrow_target: str | None = None
    pending: float = 2.0
    draw_t: float = 0.0
    drawing: bool = False


@dataclass
class Inputs:
    move: int = 0        # -1 / 0 / 1
    jump: bool = False   # そのフレームで押した(keyPressed 相当)
    vert: int = 0        # 蔦の上り下り
    draw: bool = False   # E 長押し
    aim: tuple = (1.0, 0.0)


class World:
    def __init__(self, scene_path: Path):
        self.data = json.loads(scene_path.read_text(encoding="utf-8"))
        self.ents = self.data["entities"]
        self.pos, self.scale = {}, {}
        self.gizmos, self.order = {}, []
        self.ghost = {}
        self.goal_broken = False
        self.death = None
        self.cleared = False
        self.t = 0.0

        pl_node = None
        for e in self.ents:
            n = e["name"]
            tr = e.get("transform")
            if tr is None:      # UI エンティティ(HudCanvas等)は物理に無関係
                continue
            self.pos[n] = tuple(tr["position"])
            self.scale[n] = list(tr["scale"])
            ls = e.get("luaScript")
            if not ls:
                continue
            sp = Path(ls["scriptPath"]).name
            if sp == "Player.lua":
                pl_node = _props(ls)
            elif sp == "GameManager.lua":
                self.T = _props(ls)["T"]
            elif sp == "Exit.lua":
                self.exit_name, self.exit_props = n, _props(ls)
            elif sp in SCRIPTS:
                g = SCRIPTS[sp](self, n, sp, _props(ls), self.pos[n], self.scale[n])
                self.gizmos[n] = g
                self.order.append(n)

        assert pl_node, "Player が見つからない"
        self.pp = pl_node
        self.solids = _split(pl_node["solids"])
        self.stands = _split(pl_node["standables"])
        self.climbs = _split(pl_node["climbables"])
        self.targets = _split(pl_node["targets"])
        self.stops = _split(pl_node.get("arrowStops", ""))
        p0 = self.pos["Player"]
        self.player = PlayerState(x=p0[0], y=p0[1])
        self.pos["Player"] = p0
        self.ps = self.scale["Player"]

    # -- ヘルパ -----------------------------------------------------------
    @property
    def half_w(self):
        return self.pp["halfW"]

    @property
    def half_h(self):
        return self.pp["halfHeight"]

    def hits_player(self, x, y, hw, hh):
        p = self.player
        return overlap(x, y, hw, hh, p.x, p.y, self.ps[0] * 0.5, self.ps[1] * 0.5)

    def kill(self, why):
        if self.death is None:
            self.death = why

    def time_skip(self, target, amount):
        g = self.gizmos.get(target)
        if g:
            g.skip(amount)
        b = self.gizmos.get(target)
        if isinstance(b, Button):
            b.on_arrow()

    def button_toggle(self, target):
        g = self.gizmos.get(target)
        if isinstance(g, CrushWall):
            g.button_active = not g.button_active
        elif isinstance(g, TimedDoor):
            g.button_open = not g.button_open
        elif isinstance(g, RisePlatform):
            g.button_up = not g.button_up

    def collider(self, name):
        """有効なコライダーを返す。隠れている(y<-50)/ghost中なら None。"""
        if self.ghost.get(name, 0.0) > 0:
            return None
        p = self.pos.get(name)
        if p is None or p[1] < -50:
            return None
        s = self.scale[name]
        return p[0], p[1], s[0] * 0.5, s[1] * 0.5

    # -- 物理(Player.lua と同じ順序) --------------------------------------
    def _resolve_x(self, py, nx):
        px = self.player.x
        for name in self.solids:
            c = self.collider(name)
            if not c:
                continue
            ex, ey, ehw, ehh = c
            # 0.06 のマージン: 足場の上に立っている状態を「壁に埋まっている」と誤判定しない
            if abs(py - ey) >= (self.half_h + ehh - 0.06):
                continue
            if abs(nx - ex) < (self.half_w + ehw):
                if abs(px - ex) < (self.half_w + ehw):
                    if abs(nx - ex) <= abs(px - ex):
                        nx = px
                else:
                    nx = (ex + ehw + self.half_w) if nx > ex else (ex - ehw - self.half_w)
        return nx

    def _resolve_y(self, nx, py, ny):
        p = self.player
        landed_top, landed_name = None, None
        foot_prev, foot_new = py - self.half_h, ny - self.half_h
        head_prev, head_new = py + self.half_h, ny + self.half_h

        def try_land(name, one_way, ny):
            nonlocal landed_top, landed_name
            c = self.collider(name)
            if not c:
                return ny
            ex, ey, ehw, ehh = c
            if abs(nx - ex) >= (self.half_w + ehw):
                return ny
            top = ey + ehh
            if foot_prev >= top - 0.001 and foot_new <= top:
                if landed_top is None or top > landed_top:
                    landed_top, landed_name = top, name
            if one_way:
                return ny
            bot = ey - ehh
            if head_prev <= bot + 0.001 and head_new >= bot:
                ny = bot - self.half_h
                if p.vy > 0:
                    p.vy = 0.0
            return ny

        if p.vy <= 0:
            for name in self.solids:
                ny = try_land(name, False, ny)
            for name in self.stands:
                ny = try_land(name, True, ny)
        else:
            for name in self.solids:
                ny = try_land(name, False, ny)

        if landed_top is not None:
            ny = landed_top + self.half_h
            p.vy = 0.0
            p.grounded = True
            p.ride = landed_name
        else:
            p.grounded = False
            p.ride = None
        return ny

    def _carry(self):
        p = self.player
        if not p.ride:
            return
        c = self.collider(p.ride)
        if not c:
            p.ride = None
            return
        p.x += c[0] - p.ride_px
        p.y += c[1] - p.ride_py

    def _unstick(self):
        """動く床に持ち上げられて地形へめり込んだら、重なりの浅い軸へ押し出す。"""
        p = self.player
        for name in self.solids:
            c = self.collider(name)
            if not c:
                continue
            ex, ey, ehw, ehh = c
            ox = (self.half_w + ehw) - abs(p.x - ex)
            oy = (self.half_h + ehh) - abs(p.y - ey)
            if ox > 0.0001 and oy > 0.0001:
                if oy <= ox:
                    p.y = p.y + oy if p.y > ey else p.y - oy
                    if p.vy > 0:
                        p.vy = 0.0
                else:
                    p.x = p.x + ox if p.x > ex else p.x - ox

    def _remember_ride(self):
        p = self.player
        if not p.ride:
            return
        c = self.collider(p.ride)
        if c:
            p.ride_px, p.ride_py = c[0], c[1]

    def _climb(self, inp):
        p = self.player
        p.climbing = False
        if p.drawing:
            return
        touching = False
        for name in self.climbs:
            c = self.collider(name)
            if not c:
                continue
            ex, ey, ehw, ehh = c
            if abs(p.x - ex) <= ehw + 0.3 and abs(p.y - ey) <= ehh + self.half_h * 0.6:
                touching = True
                break
        if not touching or inp.vert == 0:
            return
        p.climbing = True
        p.vx = 0.0
        p.vy = inp.vert * self.pp["climbSpeed"]

    def _move(self, inp, dt):
        p = self.player
        move = 0 if p.drawing else inp.move
        if move:
            p.facing = 1 if move > 0 else -1
        p.vx = move * self.pp["speed"]
        if (not p.drawing) and p.grounded and inp.jump:
            p.vy = self.pp["jumpSpeed"]
            p.grounded = False
        self._climb(inp)
        if not p.climbing:
            p.vy -= self.pp["gravity"] * dt

        px, py = p.x, p.y
        nx = self._resolve_x(py, px + p.vx * dt)
        ny = py + p.vy * dt
        if p.climbing:
            p.grounded = False
            p.ride = None
        else:
            ny = self._resolve_y(nx, py, ny)
        p.x, p.y = nx, ny
        self.pos["Player"] = (nx, ny, 0.0)
        self._remember_ride()
        if ny < self.pp["killY"]:
            self.kill("fell")

    # -- 矢 ---------------------------------------------------------------
    def _draw_and_fire(self, inp, dt):
        p = self.player
        can = p.has_arrow and not p.arrow_flying and not p.arrow_stuck
        if inp.draw and can:
            if not p.drawing:
                p.drawing = True
                p.draw_t = 0.0
            p.draw_t = min(p.draw_t + dt, self.pp["maxDrawTime"])
        elif p.drawing:
            p.drawing = False
            frac = max(0.0, min(p.draw_t / self.pp["maxDrawTime"], 1.0))
            amount = self.pp["minSkip"] + (self.pp["maxSkip"] - self.pp["minSkip"]) * frac
            ax, ay = inp.aim
            n = math.hypot(ax, ay) or 1.0
            ax, ay = ax / n, ay / n
            p.arrow_x, p.arrow_y = p.x + ax * 0.7, p.y + 0.2 + ay * 0.3
            p.arrow_vx = ax * self.pp["arrowSpeed"]
            p.arrow_vy = ay * self.pp["arrowSpeed"]
            p.arrow_from = (p.x, p.y)
            p.pending = amount
            p.has_arrow = False
            p.arrow_flying = True
            p.draw_t = 0.0

    def _arrow(self, dt):
        p = self.player
        ah = self.pp["arrowHalf"]
        if p.arrow_flying:
            nx, ny = p.arrow_x + p.arrow_vx * dt, p.arrow_y + p.arrow_vy * dt
            p.arrow_x, p.arrow_y = nx, ny
            hit = None
            for name in self.targets:
                c = self.collider(name)
                if c and overlap(nx, ny, ah, ah, c[0], c[1], c[2], c[3]):
                    hit = name
                    break
            terrain = False
            for name in self.stops:
                c = self.collider(name)
                if c and overlap(nx, ny, ah, ah, c[0], c[1], c[2], c[3]):
                    terrain = True
                    break
            travelled = (nx - p.arrow_from[0]) ** 2 + (ny - p.arrow_from[1]) ** 2
            if hit:
                p.arrow_flying, p.arrow_stuck, p.arrow_target = False, True, hit
                self.time_skip(hit, p.pending)
            elif terrain:
                p.arrow_flying, p.arrow_stuck, p.arrow_target = False, True, None
            elif ny < self.pp["killY"]:
                p.arrow_flying, p.arrow_stuck, p.arrow_target = False, True, None
            elif travelled > self.pp["arrowRange"] ** 2:
                p.arrow_flying, p.arrow_stuck, p.arrow_target = False, True, None
            return
        if p.arrow_stuck:
            recovered = False
            if p.arrow_target:
                c = self.collider(p.arrow_target)
                if c:
                    p.arrow_x, p.arrow_y = c[0], c[1]
                    if overlap(p.x, p.y, self.half_w, self.half_h, c[0], c[1], c[2], c[3]):
                        recovered = True
                else:
                    recovered = True
            elif overlap(p.x, p.y, self.half_w, self.half_h, p.arrow_x, p.arrow_y, ah, ah):
                recovered = True
            if recovered:
                p.arrow_stuck = False
                p.has_arrow = True
                p.arrow_target = None

    # -- 1フレーム --------------------------------------------------------
    def step(self, inp: Inputs, dt=DT):
        for k in list(self.ghost):
            self.ghost[k] -= dt
        self._carry()
        self._unstick()
        self._move(inp, dt)
        self._draw_and_fire(inp, dt)
        self._arrow(dt)
        for name in self.order:
            self.gizmos[name].update(dt)
        self.t += dt
        ex, ey, _ = self.pos[self.exit_name]
        r = self.exit_props["radius"]
        if not self.goal_broken and (ex - self.player.x) ** 2 + (ey - self.player.y) ** 2 < r * r:
            self.cleared = True
        return self.cleared, self.death

    # -- 状態のスナップショット(探索用) ------------------------------------
    def snapshot(self):
        return (
            replace(self.player),
            dict(self.pos),
            {k: list(v) for k, v in self.scale.items()},
            dict(self.ghost),
            [(g.clock, g.ff_remain, g.ff_speed, g.ghost_t,
              getattr(g, "button_active", None), getattr(g, "button_open", None),
              getattr(g, "button_up", None), getattr(g, "cur_frac", None),
              getattr(g, "was_standing", None), getattr(g, "broke", None))
             for g in (self.gizmos[n] for n in self.order)],
            self.t, self.goal_broken, self.death, self.cleared,
        )

    def restore(self, s):
        (self.player, pos, sc, gh, gz, self.t,
         self.goal_broken, self.death, self.cleared) = s
        self.pos = dict(pos)
        self.scale = {k: list(v) for k, v in sc.items()}
        self.ghost = dict(gh)
        for n, vals in zip(self.order, gz):
            g = self.gizmos[n]
            (g.clock, g.ff_remain, g.ff_speed, g.ghost_t,
             ba, bo, bu, cf, ws, br) = vals
            if ba is not None:
                g.button_active = ba
            if bo is not None:
                g.button_open = bo
            if bu is not None:
                g.button_up = bu
            if cf is not None:
                g.cur_frac = cf
            if ws is not None:
                g.was_standing = ws
            if br is not None:
                g.broke = br


def load(stage: str) -> World:
    return World(SCENES / f"{stage}.json")


def jump_metrics(w: World):
    """ジャンプの到達性能(設計に使う数値)。"""
    vj, g, sp = w.pp["jumpSpeed"], w.pp["gravity"], w.pp["speed"]
    height = vj * vj / (2 * g)
    airtime = 2 * vj / g
    return {
        "最高到達(足元)": round(height, 3),
        "滞空時間": round(airtime, 3),
        "水平到達": round(sp * airtime, 3),
        "越えられる穴幅": round(sp * airtime + 2 * w.pp["halfW"], 2),
    }
