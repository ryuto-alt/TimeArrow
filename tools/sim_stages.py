# -*- coding: utf-8 -*-
"""TimeArrow ステージ成立性シミュレータ v2(2026-07-22 全面再設計)。

モデル化(Luaと一致):
  - ギミック時計 = 実時間 + オフセット(FF+/RW-、0で底打ち)。実時間=世界時間
  - 引き絞り中は世界0.25倍速 → 引きd秒(壁時計)で世界は d*0.25 だけ進む
  - 矢: 発射→飛行(距離/15)→命中時に効果→0.9秒後に次弾可(刺さり0.4+帰還0.5)
  - タイマー = 実時間 + FF代償(量*0.5) - RW返金(実効量*0.5)
  - 【重要な物理的事実】平地の振り子ノコは歩行5u/sでは絶対に通過不能
    (追走=追突、対向=すれ違い時に必ず接触)。刃は必ず「退避ピット」構造で使う。

各ステージの機械検証: 矢なし/FFのみ/RWのみ → 失敗すべき、想定解 → マージン帯でクリア。
"""

import math
import sys
from knobs import K

WALK = 5.0
ARROW_V = 15.0
DRAW_SLOW = 0.25
STUCK_RETURN = 0.9
SAW_HALF = 0.56 + 0.4          # 刃半幅(s1.4×0.8)+プレイヤー半幅


def draw_time(amount):
    frac = max(0.0, min(1.0, (amount - 2.0) / 8.0))
    return 0.15 + frac * (3.0 - 0.15)


class Run:
    def __init__(self, limit, shots):
        self.real = 0.0
        self.timer = 0.0
        self.limit = limit
        self.shots = shots
        self.off = {}
        self.arrow_ready = 0.0
        self.log = []
        self.dead = None
        # 「単調さ」の計測: 何の判断も要らない移動だけが続いた最長の秒数。
        # レベルデザイン規範では純移動8秒以上は禁止(scratchpad/leveldesign_research.md)
        self.last_beat = 0.0
        self.max_idle = 0.0
        self.idle_at = ""

    def clock(self, name):
        return max(0.0, self.real + self.off.get(name, 0.0))

    def note(self, msg):
        self.log.append(f"  t={self.timer:5.1f}/実{self.real:5.1f}  {msg}")

    def beat(self, what=""):
        """判断や操作が起きた瞬間。ここまでの「移動だけの時間」を確定する。"""
        gap = self.real - self.last_beat
        if gap > self.max_idle:
            self.max_idle, self.idle_at = gap, what
        self.last_beat = self.real

    def advance(self, dt, scale=1.0):
        self.real += dt
        self.timer += dt * scale

    def walk(self, dist, label=""):
        self.advance(abs(dist) / WALK)
        self.note(f"walk {abs(dist):.1f}u {label}")

    def hops(self, dist, jumps, label=""):
        self.advance(abs(dist) / WALK + jumps * 0.15)
        self.note(f"hops {abs(dist):.1f}u x{jumps} {label}")

    def wait(self, dt, label=""):
        if dt > 0:
            self.advance(dt)
            self.note(f"wait {dt:.1f}s {label}")

    def shot(self, mode, target, amount, dist=5.0, label="", cap=None):
        self.beat(f"{mode.upper()}→{target} の直前")
        if self.real < self.arrow_ready:
            w = self.arrow_ready - self.real
            self.advance(w)
            self.note(f"矢の帰還待ち {w:.1f}s")
        self.advance(draw_time(amount) * DRAW_SLOW)
        self.advance(dist / ARROW_V)
        actual = 0.0
        if mode == "ff":
            self.off[target] = self.off.get(target, 0.0) + amount
            self.timer += amount * 0.5
            self.note(f"FF+{amount:g}→{target} (代償{amount * 0.5:g}) {label}")
            actual = amount
        else:
            if self.shots <= 0:
                self.dead = self.dead or f"RW残数切れ: {label}"
                return 0.0
            self.shots -= 1
            # cap=閉門型の時計頭打ち(閉まったら時間が止まる仕様)
            cur = self.clock(target) if cap is None else min(self.clock(target), cap)
            actual = min(amount, cur)
            self.off[target] = (cur - actual) - self.real
            self.timer = max(0.0, self.timer - actual * 0.5)
            self.note(f"RW-{amount:g}(実効{actual:g}, 返金{actual * 0.5:g})→{target} {label}")
        self.arrow_ready = self.real + STUCK_RETURN
        return actual

    def ff(self, target, amount, dist=5.0, label=""):
        return self.shot("ff", target, amount, dist, label)

    def rw(self, target, amount, dist=5.0, label="", cap=None):
        return self.shot("rw", target, amount, dist, label, cap=cap)

    # ── ギミック ─────────────────────────────────────────
    def fan_ride(self, name, amount, dist=1.2, climb=1.3, label=""):
        """上昇気流ファン: FFサージ(量×0.8秒)を焚いて気流に乗り、棚まで浮上する。
        RW矢は吸い込み(引き寄せ)にしかならず高所へは運ばない=FF専用の高度獲得手段。"""
        self.beat(f"ファン{name} の直前")
        self.ff(name, amount, dist, label=f"サージ点火 {label}")
        assert amount * 0.8 >= climb, f"{name}: サージ{amount * 0.8:.1f}s < 上昇{climb}s"
        self.advance(climb)
        self.note(f"ファン{name} の気流で浮上 {climb:.1f}s {label}")

    def ferry_ride(self, name, period, span, wait_frac=0.25, label=""):
        """横行フェリー: 寄ってくるのを待って乗り、対岸で降りる。乗り遅れは奈落=判断の拍。"""
        self.beat(f"フェリー{name} の直前")
        self.wait(period * wait_frac, f"フェリー{name}の間合い")
        self.advance(period * 0.5)
        self.note(f"フェリー{name}で {span:.1f}u 渡る ({period * 0.5:.1f}s) {label}")

    def crumble_run(self, names, span, crumbleT=1.5, label=""):
        """崩れ足場: 踏んだら崩れ始めるので止まれない。渡り切れるかが判断の拍。"""
        self.beat(f"崩れ足場{names[0]} の直前")
        dur = span / WALK
        assert dur < crumbleT * len(names),             f"崩れ足場{names}: 横断{dur:.2f}s >= 崩壊{crumbleT * len(names):.2f}s"
        self.advance(dur)
        self.note(f"崩れ足場{'/'.join(names)}を一気に渡る ({span:.1f}u, {dur:.1f}s) {label}")

    def hammer_pass(self, name, period, label=""):
        """振り子ハンマー: 平地で唯一タイミングで渡れる刃。間合いを計るのが判断の拍。"""
        self.beat(f"ハンマー{name} の直前")
        self.wait(period * 0.28, f"ハンマー{name}の間合い")
        self.advance(0.5)
        self.note(f"ハンマー{name}の下を抜ける {label}")

    def needle_down(self, name, dist=2.5, label=""):
        """起立針山: RW矢1発で寝かせる(時計を持たないので返金なし)。FFでは寝ない。"""
        self.beat(f"起立針山{name} の直前")
        if self.real < self.arrow_ready:
            w = self.arrow_ready - self.real
            self.advance(w)
            self.note(f"矢の帰還待ち {w:.1f}s")
        self.advance(draw_time(2.0) * DRAW_SLOW)
        self.advance(dist / ARROW_V)
        if self.shots <= 0:
            self.dead = self.dead or f"RW残数切れ: 起立針山{name}を寝かせられない"
            return
        self.shots -= 1
        self.note(f"RW→起立針山{name} を寝かせる (残数消費, 返金なし) {label}")
        self.arrow_ready = self.real + STUCK_RETURN
        self.advance(0.45)
        self.note(f"針山{name} が寝転がるのを待つ 0.5s")

    def lock_wait(self, name, openT, label=""):
        self.beat(f"錠{name} の直前")
        c = self.clock(name)
        if c < openT:
            self.advance(openT - c)
            self.note(f"錠{name} 開待ち {openT - c:.1f}s {label}")
        self.advance(0.9)
        self.note(f"錠{name} を通過")

    def gate_pass(self, name, closeT, label=""):
        self.beat(f"閉門{name} の直前")
        c = self.clock(name)
        if c >= closeT:
            self.dead = self.dead or f"閉門{name}済み(時計{c:.1f} >= 閉{closeT}) {label}"
        else:
            self.note(f"閉門{name} 通過 (時計{c:.1f} < {closeT}, 余裕{closeT - c:.1f}s) {label}")
        self.advance(0.2)

    def gate_reopen_pass(self, name, closeT, label=""):
        self.beat(f"閉門{name} の直前")
        c = self.clock(name)
        if c >= closeT:
            self.dead = self.dead or f"閉門{name} RW不足(時計{c:.1f} >= {closeT}) {label}"
            return
        self.advance(0.7)
        if self.clock(name) >= closeT:
            self.dead = self.dead or f"閉門{name} スライド中に再閉鎖 {label}"
            return
        self.note(f"閉門{name} 再開通過 (残り窓{closeT - self.clock(name):.1f}s) {label}")
        self.advance(0.2)

    def pit_cross(self, name, bx, amp, period, phase, pit0, pit1, x0, x1, label=""):
        """退避ピット式の刃越え: 縁→ピットに入る→頭上通過を待つ→反対側へ出る"""
        self.beat(f"刃{name} の直前")
        base = self.clock(name)

        def saw(t):
            return bx + amp * math.sin(((phase + base + t) / period) * 2 * math.pi)

        def leg_safe(t, a, b, extra=0.0):
            dur = abs(b - a) / WALK + extra
            n = 20
            for i in range(n + 1):
                px = a + (b - a) * i / n
                if abs(px - saw(t + dur * i / n)) < SAW_HALF:
                    return None
            return dur

        ext = amp + SAW_HALF
        for px, side in ((x0, "入口"), (x1, "出口")):
            if abs(px - bx) < ext:
                self.dead = self.dead or f"刃{name} {side}待機位置x{px}が可動域内(|{px}-{bx}|<{ext:.2f}) {label}"
                return

        def bands(leg_a, leg_b, t_from, extra=0.0):
            """t_from以降の安全帯(開始時刻, 長さ)を列挙。幅1.2s以上の帯だけ返す"""
            out = []
            t = t_from
            cur = None
            while t < t_from + 3.0 * period:
                if leg_safe(t, leg_a, leg_b, extra) is not None:
                    if cur is None:
                        cur = t
                else:
                    if cur is not None:
                        out.append((cur, t - cur))
                        cur = None
                t += 0.05
            if cur is not None:
                out.append((cur, t - cur))
            return [b for b in out if b[1] >= 1.2]

        in_bands = bands(x0, pit0, 0.0)
        if not in_bands:
            self.dead = self.dead or f"刃{name} 幅1.2s以上の進入帯がない(スキル依存) {label}"
            return
        start, win = in_bands[0]
        d1 = leg_safe(start, x0, pit0)
        t2 = start + d1 + 0.25                      # ピットへ降りる
        out_bands = bands(pit1, x1, t2, extra=0.3)
        if not out_bands:
            self.dead = self.dead or f"刃{name} 幅1.2s以上の脱出帯がない(スキル依存) {label}"
            return
        t3 = out_bands[0][0]
        total = t3 + leg_safe(t3, pit1, x1, 0.3) - 0.0
        self.wait(start, f"刃{name}の間合い")
        self.advance(total - start)
        self.note(f"刃{name} ピット横断 ({total - start:.1f}s, 進入帯{win:.1f}s/脱出帯{out_bands[0][1]:.1f}s) {label}")

    def ball_x(self, name, bx, rollT, speed, axis=1):
        return bx + axis * speed * max(0.0, self.clock(name) - rollT)

    def goal_alive(self, name, bx, rollT, speed, goal_x, axis=1, label=""):
        x = self.ball_x(name, bx, rollT, speed, axis)
        if (x - goal_x) * axis >= -0.9:
            self.dead = self.dead or f"大玉{name}がゴール破壊 (x={x:.1f}) {label}"
        else:
            self.note(f"大玉{name} ゴールまで{abs(goal_x - x):.1f}u {label}")

    def ball_block_check(self, name, bx, rollT, speed, px, axis=1, label=""):
        x = self.ball_x(name, bx, rollT, speed, axis)
        if abs(x - px) < 1.1:
            self.dead = self.dead or f"大玉{name}に接触 (x={x:.1f}≈{px}) {label}"

    def bomb_wait_boom(self, name, boomT, label=""):
        # 矢起爆式: 爆弾は自走しない。先送り累計(off)が boomT に達していなければ未起爆
        fuse = self.off.get(name, 0.0)
        if fuse < boomT:
            self.dead = self.dead or f"爆弾{name} 未起爆 (FF累計{fuse:g} < {boomT:g})"
            return
        self.advance(0.3)
        self.note(f"爆弾{name} 起爆 (FF累計{fuse:g}s) {label}")

    def finish(self):
        self.beat("ゴールまで")
        if self.dead:
            return f"✗ 失敗: {self.dead}"
        if self.timer >= self.limit:
            return f"✗ タイムアップ (t={self.timer:.1f} >= {self.limit})"
        return f"✓ クリア t={self.timer:.1f}/{self.limit} (マージン{self.limit - self.timer:.1f})"


def report(name, limit, shots, plans, margin=(1.5, 6.0), quiet=False):
    print(f"\n{'━' * 68}\n■ {name} (制限{limit}s / RW{shots})")
    ok = True
    for label, fn, should_pass in plans:
        r = Run(limit, shots)
        fn(r)
        v = r.finish()
        passed = v.startswith("✓")
        if should_pass:
            m = limit - r.timer
            good = passed and margin[0] <= m <= margin[1]
            if not good:
                ok = False
            idle_ok = r.max_idle <= 8.0
            if not idle_ok:
                ok = False
            print(f" {'✓' if good else '✗✗'} {label}: {v}"
                  + ("" if good else f"  ← マージン帯{margin}外"))
            print(f"    判断の間隔: 最長 {r.max_idle:.1f}s の純移動 ({r.idle_at})"
                  + ("" if idle_ok else "  ← ✗✗ 8秒超=単調"))
            if not quiet or not good:
                for l in r.log:
                    print(l)
        else:
            good = not passed
            if not good:
                ok = False
            print(f" {'✓' if good else '✗✗ 抜け道!!'} {label}(失敗すべき): {v}")
            if not good:
                for l in r.log:
                    print(l)
    return ok


ALL_OK = True

# ════════════════════════════════════════════════════════════════════
# S1「遅すぎる橋」2連橋(幅45, RW1) — gen_stages.py 座標に一致
# FloorA[0,14] Bridge1 x17(span14-20) FloorB[20,30] Bridge2 x33(span30-36)
# FloorC[36,45] 出口43。橋の時計 clock=real+off、riseTime到達で全下降。
# ════════════════════════════════════════════════════════════════════
S1 = K["s1"]


def s1_noarrow(r):
    r.walk(13.0, "FloorA奥(x14)へ")
    r.wait(max(0.0, S1["rise1"] - r.clock("Bridge1")), "橋1自然降下待ち")
    r.walk(6.0, "橋1を渡る")
    r.walk(10.0, "FloorB横断(x30)")
    r.dead = "橋2はrise2秒で上がりきって届かない(後戻し矢でしか降ろせない)"


def s1_plan(r):
    # x1で射程18ぎりぎりのBridge1を即射→FloorA奥へ歩く間に降下が進む
    r.ff("Bridge1", 10.0, dist=17.2, label="出発点から橋1へフル加速")
    r.walk(13.0, "FloorA奥(x14)へ")
    r.wait(max(0.0, S1["rise1"] - r.clock("Bridge1")), "残りの降下待ち")
    r.walk(6.0, "橋1を渡る")
    r.walk(9.0, "FloorB横断(橋2の縁x29.5へ)")
    r.rw("Bridge2", 10.0, dist=4.5, label="上がりきった橋2をフルで引き戻す", cap=S1["rise2"])
    r.walk(6.5, "降りてきた橋2をすぐ渡る(再上昇する前に)")
    r.walk(7.0, "ゴールへ")


def s1_ffonly(r):
    r.ff("Bridge1", 10.0, dist=17.2, label="橋1はFFで降りる")
    r.walk(13.0)
    r.wait(max(0.0, S1["rise1"] - r.clock("Bridge1")))
    r.walk(6.0, "橋1を渡る")
    r.walk(10.0, "FloorB横断")
    r.ff("Bridge2", 10.0, dist=4.5, label="FFは橋2を上げるだけ(逆効果)")
    r.dead = "橋2は先送りでは戻らない(上がりきって時計停止)"


ALL_OK &= report("S1 二つの橋(FF橋+RW橋)", S1["limit"], S1["rw"], [
    ("矢なし", s1_noarrow, False),
    ("FFのみ(橋2は上がるだけ)", s1_ffonly, False),
    ("想定解", s1_plan, True),
], margin=(1.5, 8.0))

# ════════════════════════════════════════════════════════════════════
# S2「四枚の閉門回廊」v4(幅52, RW3) — 全門が到達直前に閉まる。
# RW3では4枚に足りない→最低1枚はスプリントで間に合わせる。道中にハンマー/弾幕/崩れ橋。
# ════════════════════════════════════════════════════════════════════
S2 = K["s2"]


def s2_route_to_A(r):
    r.walk(3.0, "P2aへ")
    r.needle_down("P2aN", label="起立針山1")
    r.hops(1.6, 2, "針山1(寝かせて跳び越す)")
    r.walk(2.6, "P2bへ")
    r.hops(1.6, 2, "針山2")
    r.walk(2.4, "GateA前")


def s2_noarrow(r):
    r.walk(3.0, "P2aへ")
    r.dead = "起立針山P2aNは後戻し矢でしか寝かせられない→通れない"


def s2_ffonly(r):
    r.walk(3.0, "P2aへ")
    r.ff("P2aN", 2.0, dist=2.5, label="FFは針山を起こす向き(既に起立)")
    r.dead = "起立針山P2aNは後戻し矢でしか寝ない→通れない"


def s2_plan(r):
    s2_route_to_A(r)
    r.rw("GateA", 6.0, dist=1.5, label="スラムA呼び戻し", cap=S2["closeA"])
    r.gate_reopen_pass("GateA", S2["closeA"])
    r.walk(3.0, "ハンマー前")
    r.wait(0.8, "ハンマーの間合い")
    r.walk(6.4, "GateBへ走る")
    r.gate_pass("GateB", S2["closeB"], "スプリント成功なら矢いらず")
    r.wait(0.6, "弾幕の谷を待つ")
    r.walk(2.9, "P2cへ")
    r.needle_down("P2cN", label="起立針山2")
    r.hops(1.6, 2, "針山3(寝かせて跳び越す)")
    r.walk(5.2, "GateC前")
    r.rw("GateC", 8.0, dist=1.5, label="間に合わなければ呼び戻す", cap=S2["closeC"])
    r.gate_reopen_pass("GateC", S2["closeC"])
    r.walk(3.3, "崩れ橋へ")
    r.walk(3.2, "崩れ橋を渡り切る(1.6秒以内)")
    r.walk(1.4, "GateD前")
    r.rw("GateD", 8.0, dist=1.5, label="呼び戻し(3発目)", cap=S2["closeD"])
    r.gate_reopen_pass("GateD", S2["closeD"])
    r.walk(4.4, "ゴール")


ALL_OK &= report("S2 四枚の閉門回廊", S2["limit"], S2["rw"], [
    ("矢なし", s2_noarrow, False),
    ("FFのみ", s2_ffonly, False),
    ("想定解", s2_plan, True),
], margin=(2.0, 14.0))

# ════════════════════════════════════════════════════════════════════
# S3「風の谷」(幅58, RW2) — gen_stages.py 座標に一致
# F3a[0,21] 射撃台x6.6/7.8 谷1[21,27]=Bridge3(x24) F3b[27,37] Fan3 x30
# 棚L3a[31.5,37.5](上面5.4) 崩れ足場[37.8,41.2] 棚L3b[41.4,47.4]
# 谷2[37,44] F3c[44,58] GateZ3 x50 出口54
# ════════════════════════════════════════════════════════════════════
S3 = K["s3"]


def s3_to_step(r):
    r.walk(2.2, "針山へ")
    r.needle_down("P3aN", label="起立針山")
    r.hops(1.6, 2, "針山(寝かせて跳び越す)")
    r.walk(2.0, "射撃台(x6.6)へ")
    r.hops(1.2, 2, "二段の段差を登る")


def s3_cross_valley1(r):
    r.walk(13.2, "谷1の縁(x21)へ")
    r.wait(max(0.0, S3["rise3"] - r.clock("Bridge3")), "橋の残り降下待ち")
    r.walk(6.5, "橋を渡る(x27.5)")
    r.walk(2.5, "ファン(x30)の上に立つ")


def s3_ledge_to_gate(r):
    r.walk(4.5, "棚L3aを東へ(x36)")
    r.crumble_run(["CrA3", "CrB3"], 5.5, label="(谷2の上)")
    r.walk(4.0, "棚L3bの東端(x45.5)へ")
    r.wait(0.4, "地上へ飛び降りる")
    r.walk(3.3, "GateZ3前(x48.8)へ")


def s3_noarrow(r):
    r.walk(2.2, "針山へ")
    r.dead = "起立針山P3aNは後戻し矢でしか寝かせられない→通れない"


def s3_ffonly(r):
    r.walk(2.2, "針山へ")
    r.ff("P3aN", 2.0, dist=2.5, label="FFは針山を起こす向き(既に起立)")
    r.dead = "起立針山P3aNは後戻し矢でしか寝ない→通れない"


def s3_ffonly_old(r):
    s3_to_step(r)
    r.ff("Bridge3", 10.0, dist=16.3, label="橋へ1本目")
    r.ff("Bridge3", 10.0, dist=16.3, label="橋へ2本目")
    s3_cross_valley1(r)
    r.fan_ride("Fan3", 6.0, dist=1.2, label="棚へ")
    s3_ledge_to_gate(r)
    r.gate_pass("GateZ3", S3["closeZ"], "到着時にはとっくに閉まっている")


def s3_rwonly(r):
    s3_to_step(r)
    s3_cross_valley1(r)
    r.rw("Fan3", 10.0, dist=1.2, label="RWは吸い込み(引き寄せ)=上には運ばない")
    r.dead = "後戻り矢ではファンはサージしない(吸い込みになるだけ)→棚に上がれない"


def s3_plan(r):
    s3_to_step(r)
    r.ff("Bridge3", 10.0, dist=16.3, label="射撃台から橋へ1本目")
    r.ff("Bridge3", 10.0, dist=16.3, label="橋へ2本目(降下を前借り)")
    s3_cross_valley1(r)
    r.fan_ride("Fan3", 6.0, dist=1.2, label="サージで棚(5.4u)へ")
    s3_ledge_to_gate(r)
    r.rw("GateZ3", 10.0, dist=1.2, label="閉じきった門を呼び戻す", cap=S3["closeZ"])
    r.gate_reopen_pass("GateZ3", S3["closeZ"])
    r.walk(4.6, "ゴール")


ALL_OK &= report("S3 風の谷(橋+ファン+崩れ足場)", S3["limit"], S3["rw"], [
    ("矢なし", s3_noarrow, False),
    ("FFのみ", s3_ffonly, False),
    ("RWのみ", s3_rwonly, False),
    ("想定解", s3_plan, True),
], margin=(2.0, 10.0))

# ════════════════════════════════════════════════════════════════════
# S4「昇降の工房」(幅64, RW2) — gen_stages.py 座標に一致
# F4a[0,18.8] GateA4 x13(スラム) 刃ピットbx19.4 F4b[20,31] Ham4 x27
# 谷[31,39]=Ferry4(x35,振幅3.2) F4c[39,50] Lock4 x49(x39から水平種まき)
# 谷[50,64]=Elev4(x51.5,上下2.3) レッジ[53.2,57.2] 崩れ[57.2,60.6] [60.6,64] 出口62.5
# ════════════════════════════════════════════════════════════════════
S4 = K["s4"]
S4_SAW = dict(bx=19.4, amp=1.0, period=4.0, phase=0.0, pit0=18.8, pit1=20.0)


def s4_route_to_A(r):
    r.walk(3.2, "P4aへ")
    r.needle_down("P4aN", label="起立針山1")
    r.hops(1.7, 2, "針山1(寝かせて跳び越す)")
    r.walk(3.1, "P4bへ")
    r.needle_down("P4bN", label="起立針山2")
    r.hops(1.6, 2, "針山2(寝かせて跳び越す)")
    r.walk(2.6, "GateA4前")


def s4_mid(r, ferry_wait):
    """刃ピット→ハンマー→フェリーで谷を渡ってx39へ"""
    r.walk(3.6, "刃ピット手前(x16.6)へ")
    r.pit_cross("Saw4", **S4_SAW, x0=16.6, x1=22.1, label="退避ピットで刃越え")
    r.walk(3.4, "ハンマー手前(x25.5)へ")
    r.hammer_pass("Ham4", 3.4)
    r.walk(5.5, "谷の縁(x31)へ")
    r.ferry_ride("Ferry4", S4["ferryP"], 8.0, wait_frac=ferry_wait)


def s4_noarrow(r):
    r.walk(3.2, "P4aへ")
    r.dead = "起立針山P4aNは後戻し矢でしか寝かせられない→通れない"


def s4_rwonly(r):
    s4_route_to_A(r)
    r.rw("GateA4", 4.0, dist=1.5, label="スラムA(#1)", cap=S4["slamA"])
    r.gate_reopen_pass("GateA4", S4["slamA"])
    s4_mid(r, ferry_wait=0.5)     # 位相を手繰れないので最悪待ち
    r.walk(9.6, "Lock4前(x48.6)")
    r.lock_wait("Lock4", S4["lockZ"], "種まき無し=自然開通まで丸ごと待つ")
    r.walk(1.4, "谷の縁(x50)へ")
    r.wait(S4["elevP"] * 0.5, "昇降足場が下りてくるのを待つ")
    r.advance(1.6)
    r.note("昇降足場でレッジへ")
    r.walk(3.0, "レッジを東へ")
    r.crumble_run(["CrA4", "CrB4"], 4.4)
    r.walk(1.9, "ゴール")


def s4_plan(r):
    s4_route_to_A(r)
    r.rw("GateA4", 10.0, dist=1.5, label="スラムA呼び戻し(#1)", cap=S4["slamA"])
    r.gate_reopen_pass("GateA4", S4["slamA"])
    s4_mid(r, ferry_wait=0.25)
    r.ff("Lock4", 10.0, dist=10.5, label="◆種まき1: 対岸に着いた瞬間に終錠へ(水平射)")
    r.ff("Lock4", 10.0, dist=10.5, label="◆種まき2")
    r.walk(9.6, "Lock4前(x48.6)")
    r.lock_wait("Lock4", S4["lockZ"], "種まき済みでほぼ待たない")
    r.walk(1.4, "谷の縁(x50)へ")
    r.ff("Elev4", 2.0, dist=1.8, label="昇降足場の位相を手繰り寄せる(最小引き)")
    r.wait(0.4, "下りてきた足場に乗る")
    r.advance(1.6)
    r.note("昇降足場でレッジ(5.4u)へ")
    r.walk(3.0, "レッジを東へ")
    r.crumble_run(["CrA4", "CrB4"], 4.4)
    r.walk(1.9, "ゴール")


ALL_OK &= report("S4 昇降の工房(フェリー+昇降足場+種まき)", S4["limit"], S4["rw"], [
    ("矢なし", s4_noarrow, False),
    ("FFのみ", s4_noarrow, False),
    ("RWのみ", s4_rwonly, False),
    ("想定解", s4_plan, True),
], margin=(2.0, 10.0))

# ════════════════════════════════════════════════════════════════════
# S5「時の昇降機・改」(幅88, RW4, 3層) — gen_stages.py 座標に一致
# StepA5 x4.2/N5 x4.9/StepB5 x5.6 Lift5 x12.5 デッキ[16,52] Gate5 x17.2 Ham5 x24
# Ball5 x19.5 PitR1F x28.6 LockD5 x46 Vine5 x61.2 最上層[62,88] Ferry5 x72
# 最上層の崩れ足場[77,80.4] LockZ5 x82 出口85.5
# ════════════════════════════════════════════════════════════════════
S5 = K["s5"]
S5_BALL = dict(bx=19.5, rollT=S5["ballRoll"], speed=S5["ballSpeed"])
S5_GOAL = 85.5


def s5_ground(r):
    r.walk(3.4, "針山へ")
    r.hops(1.4, 2, "針山")
    r.walk(2.4, "リフト射撃位置x8へ")


def s5_noarrow(r):
    s5_ground(r)
    r.wait(14.0, "リフト自然降下")
    r.dead = "デッキへ上がる手段がない(リフトはRWでしか上がらない)"


def s5_ffonly(r):
    s5_ground(r)
    r.ff("Lift5", 10.0, dist=4.5)
    r.ff("Lift5", 4.0, dist=4.5)
    r.dead = "リフトは降ろせても上がれない(デッキ到達不能)"


def s5_rwonly(r):
    s5_ground(r)
    r.wait(max(0.0, S5["lift"] - r.clock("Lift5")), "自然降下待ち")
    r.walk(4.5, "乗り込み")
    r.rw("Lift5", 10.0, dist=0.5, label="巻き上げ(#1)")
    r.wait(0.6)
    r.walk(4.7, "スラム前")
    r.rw("Gate5", 4.0, dist=1.0, label="スラムGを呼び戻す(#2)", cap=S5["slamG"])
    r.gate_reopen_pass("Gate5", S5["slamG"])
    r.walk(4.5, "ハンマー手前へ")
    r.hammer_pass("Ham5", 3.2)
    r.walk(6.9, "退避ピット1へ")
    r.wait(0.3, "ピットに降りる")
    r.rw("Ball5", 10.0, dist=2.5, label="大玉を呼び戻す(#3)")
    r.wait(0.8)
    r.wait(0.3)
    r.walk(17.4, "LockD前(種まき無し)")
    r.lock_wait("LockD5", S5["lockD"], "自然開通まで待つ")
    r.walk(6.0, "デッキ端52で降りる")
    r.wait(0.3, "地上へ")
    r.walk(9.2, "Vine5前")
    r.wait(max(0.0, S5["vineGrow"] - r.clock("Vine5")), "ツタの自然成長待ち(長い)")
    r.wait(2.2, "ツタを登る")
    r.crumble_run(["CrC5", "CrD5"], 3.4, label="(最上層)")
    r.walk(5.9, "LockZ5前へ")
    r.rw("LockZ5", 10.0, dist=1.0, label="最後の1発(#4=予算オーバー)")


def s5_plan(r):
    s5_ground(r)
    r.ff("Lift5", 10.0, dist=4.5, label="リフトへ1本目")
    r.ff("Lift5", 4.0, dist=4.5, label="リフトへ2本目(時計がlift到達)")
    r.walk(4.5, "乗り込み")
    r.rw("Lift5", 10.0, dist=0.5, label="乗ったまま巻き上げ=上昇!(#1)")
    r.wait(0.6, "デッキへ移る")
    r.walk(4.7, "スラム前")
    r.rw("Gate5", 10.0, dist=1.0, label="呼び戻し(時計が若く1発, #2)")
    r.gate_reopen_pass("Gate5", S5["slamG"])
    r.walk(4.5, "ハンマー手前へ")
    r.hammer_pass("Ham5", 3.2, "(大玉が迫る)")
    r.walk(6.9, "退避ピット1へ")
    r.wait(0.3, "ピットに降りる")
    r.rw("Ball5", 10.0, dist=2.5, label="大玉を呼び戻す(頭上を逆走, #3)")
    r.wait(0.8, "通過待ち")
    r.wait(0.3, "ピットから出る")
    r.walk(3.4, "種まき位置(x32)へ")
    r.ff("LockD5", 10.0, dist=14.0, label="◆種まき: 終錠Dへ")
    r.walk(14.0, "デッキを進む(x46)")
    r.lock_wait("LockD5", S5["lockD"])
    r.walk(6.0, "デッキ端52で降りる")
    r.wait(0.3, "地上へ飛び降りる")
    r.walk(9.2, "Vine5前(x61.2)")
    r.ff("Vine5", 10.0, dist=1.0, label="ツタへ1本目")
    r.ff("Vine5", 10.0, dist=1.0, label="ツタへ2本目(即育つ)")
    r.lock_wait("Vine5", S5["vineGrow"])
    r.wait(2.2, "ツタを登る(climbSpeed4)")
    r.walk(4.8, "種まき位置(x66)へ")
    r.ff("LockZ5", 10.0, dist=16.0, label="◆種まき: 終錠Zへ(フェリー手前)")
    r.walk(4.0, "フェリー乗り場(x70)へ")
    r.ferry_ride("Ferry5", S5["ferryP"], 4.4)
    r.walk(2.5, "最上層の谷の縁(x77)へ")
    r.crumble_run(["CrC5", "CrD5"], 3.4, label="(最上層)")
    r.walk(2.1, "LockZ5前")
    r.lock_wait("LockZ5", S5["lockZ"])
    r.goal_alive("Ball5", **S5_BALL, goal_x=S5_GOAL, label="レース勝利")
    r.walk(3.5, "ゴール")


# (stage4まで構成: S5 のreportは封印中)

# ════════════════════════════════════════════════════════════════════
# S6「導火線と気流」(幅96, RW2, 2層) — gen_stages.py 座標に一致
# F6a[0,16] 針山3つ 谷[16,20.5]=RevB6(逆橋) F6b[20.5,96] Bomb6 x24/WallW6 x25
# Fan6 x29 レッジ[30.5,64] Sill6 x32.5(バイパス封鎖) Bomb62 x44/WallW62 x45.4
# CW6 x52(錆びた動く壁) Ham6 x70.5 LockZ6 x80 Tur6 x86.5 出口92
# ════════════════════════════════════════════════════════════════════
S6 = K["s6"]


def s6_to_valley(r):
    r.walk(3.6, "P6aへ")
    r.hops(1.7, 2, "針山1")
    r.walk(3.3, "P6bへ")
    r.hops(1.6, 2, "針山2")
    r.walk(2.0, "P6xへ")
    r.hops(1.6, 2, "針山3")
    r.walk(1.4, "谷の縁(x16)へ")
    assert r.real > S6["rev6"], f"逆橋: 到着{r.real:.2f}s <= 上昇完了{S6['rev6']}s(早乗りできてしまう)"


def s6_after_bridge(r):
    """逆橋を渡った後: 爆弾1で壁を割ってファンの足元まで"""
    r.walk(5.0, "橋を渡り切る(x20.5)")
    r.walk(1.0, "爆風圏の外(x21.5)で構える")


def s6_noarrow(r):
    s6_to_valley(r)
    r.dead = f"逆橋は{S6['rev6']}秒で上がりきり、そのまま時計が止まる=矢なしでは谷を渡れない"


def s6_ffonly(r):
    s6_to_valley(r)
    r.ff("RevB6", 10.0, dist=2.5, label="FFは上がりきった橋をさらに未来へ送るだけ")
    r.dead = "先送りでは逆橋は戻らない(上がりきって時計停止)"


def s6_rwonly(r):
    s6_to_valley(r)
    r.rw("RevB6", 10.0, dist=2.5, label="逆橋を引き戻す(#1)", cap=S6["rev6"])
    s6_after_bridge(r)
    r.dead = "後戻り矢では爆弾Bomb6を起爆できない→壁W6が壊れず先へ進めない"


def s6_plan(r):
    s6_to_valley(r)
    r.rw("RevB6", 10.0, dist=2.5, label="上がりきった逆橋を引き戻す(#1)", cap=S6["rev6"])
    s6_after_bridge(r)
    r.ff("Bomb6", 5.0, dist=2.6, label="起爆矢(累計5秒で爆発、安全圏から)")
    r.bomb_wait_boom("Bomb6", S6["boom1"])
    r.walk(7.5, "瓦礫を抜けてファン(x29)の上へ")
    r.fan_ride("Fan6", 6.0, dist=1.4, label="サージでレッジ(4.4u)へ")
    r.walk(11.5, "レッジを東へ(x42)")
    r.ff("Bomb62", 5.0, dist=2.2, label="起爆矢(レッジ上からしか撃てない)")
    r.bomb_wait_boom("Bomb62", S6["boom2"])
    r.walk(6.6, "瓦礫を抜けてCW6前(x51)へ")
    r.ff("CW6", 2.0, dist=1.5, label="錆びた壁をゴースト化(最小引きで足りる)")
    r.wait(0.4, "実体が薄れている間にすり抜ける")
    r.walk(12.0, "レッジ端(x64)へ")
    r.wait(0.3, "地上へ降りる")
    r.walk(2.0, "種まき位置(x66)へ")
    r.ff("LockZ6", 10.0, dist=14.0, label="◆種まき: 終錠へ(水平)")
    r.walk(2.0, "P6cへ")
    r.hops(1.7, 2, "針山3")
    r.hammer_pass("Ham6", 3.2)
    r.walk(3.3, "P6dへ")
    r.hops(1.7, 2, "針山4")
    r.walk(5.3, "LockZ6前")
    r.lock_wait("LockZ6", S6["lockZ"])
    r.walk(12.0, "ゴール")


# (stage4まで構成: S6 のreportは封印中)

# ════════════════════════════════════════════════════════════════════
# S7「時計塔大回廊」(幅104, RW4, 3層) — gen_stages.py 座標に一致
# P7a[3.4,5.0] P7b[7.2,8.8] GateA7 x11.4 地上東進→階段62.3-64.4→デッキ[18,60.8]
# Pit2F x50.8(sawP2) Pit1F x38.8(sawP1) LockD7 x22 Button1(x17,y5.45)
# LatticeL1 x68.5 Vine7 x72.5 最上層[74,104] Pit3F x86.8(sawP3) LockZ7 x98 出口101.5
# ════════════════════════════════════════════════════════════════════
S7 = K["s7"]
S7_SAW2 = dict(bx=50.8, amp=1.0, phase=0.0, pit0=51.6, pit1=50.0)
S7_SAW1 = dict(bx=38.8, amp=1.2, phase=0.0, pit0=39.6, pit1=38.0)
S7_SAW3 = dict(bx=86.8, amp=1.0, phase=0.0, pit0=86.0, pit1=87.6)


def s7_route_to_A(r):
    r.walk(2.0, "P7aへ")
    r.hops(1.6, 2, "針山1")
    r.walk(2.2, "P7bへ")
    r.hops(1.6, 2, "針山2")
    r.walk(1.2, "P7cへ")
    r.hops(1.6, 2, "針山3")
    r.walk(0.4, "谷の縁(x12)へ")
    assert r.real > S7["rev7"], f"逆橋: 到着{r.real:.2f}s <= 上昇完了{S7['rev7']}s(早乗りできてしまう)"


def s7_noarrow(r):
    s7_route_to_A(r)
    r.dead = "逆橋は上空へ去っていく=矢なしでは谷[12,16.5]を渡れない"


def s7_rwonly(r):
    s7_route_to_A(r)
    r.rw("RevB7", 10.0, dist=2.5, label="逆橋を引き戻す", cap=S7["rev7"])
    r.walk(5.0, "橋を渡る(x16.5)")
    r.walk(12.5, "地上を東へ(ハンマーa手前 x29)")
    r.hammer_pass("Ham7a", 3.4)
    r.walk(22.0, "ハンマーb手前(x51)へ")
    r.hammer_pass("Ham7b", 2.6)
    r.walk(10.0, "階段(x62)へ")
    r.hops(2.1, 4, "階段でデッキへ")
    r.walk(11.6, "デッキを西へ(刃ピット2手前)")
    r.pit_cross("Saw7b", **S7_SAW2, period=S7["sawP2"], x0=52.8, x1=48.6)
    r.walk(6.6, "刃ピット1手前へ")
    r.pit_cross("Saw7a", **S7_SAW1, period=S7["sawP1"], x0=42.0, x1=35.6)
    r.walk(13.6, "LockD7前")
    r.lock_wait("LockD7", S7["lockD"])
    r.walk(3.0, "デッキ西端(x19)へ")
    r.dead = "RW矢はButton1に反応しない(FF専用)→格子L1が開かず先へ進めない"


def s7_plan(r):
    s7_route_to_A(r)
    r.rw("RevB7", 10.0, dist=2.5, label="上がりきった逆橋を引き戻す", cap=S7["rev7"])
    r.walk(5.0, "橋を渡る(x16.5)")
    r.walk(12.5, "地上を東へ(ハンマーa手前 x29)")
    r.hammer_pass("Ham7a", 3.4)
    r.walk(22.0, "ハンマーb手前(x51)へ")
    r.hammer_pass("Ham7b", 2.6)
    r.walk(10.0, "階段(x62)へ")
    r.hops(2.1, 4, "階段でデッキへ")
    r.walk(11.6, "デッキを西へ(刃ピット2手前)")
    r.pit_cross("Saw7b", **S7_SAW2, period=S7["sawP2"], x0=52.8, x1=48.6, label="(西向き)")
    r.walk(6.6, "刃ピット1手前へ")
    r.pit_cross("Saw7a", **S7_SAW1, period=S7["sawP1"], x0=42.0, x1=35.6, label="(西向き)")
    r.walk(13.6, "LockD7前")
    r.ff("LockD7", 10.0, dist=1.5, label="錠Dへ1本目")
    r.ff("LockD7", 8.0, dist=1.5, label="錠Dへ2本目(待つより得)")
    r.lock_wait("LockD7", S7["lockD"])
    r.walk(3.0, "デッキ西端(x19)へ")
    r.ff("Button1", 2.0, dist=2.4, label="塔上のボタンへFF矢→格子L1が開く")
    r.walk(16.6, "デッキを東へ引き返す(刃ピット1へ)")
    r.pit_cross("Saw7a", bx=38.8, amp=1.2, phase=0.0, pit0=38.0, pit1=39.6,
                period=S7["sawP1"], x0=35.6, x1=42.0, label="(東向き)")
    r.walk(6.6, "刃ピット2へ")
    r.pit_cross("Saw7b", bx=50.8, amp=1.0, phase=0.0, pit0=50.0, pit1=51.6,
                period=S7["sawP2"], x0=48.6, x1=52.8, label="(東向き)")
    r.walk(10.5, "デッキ東端へ")
    r.hops(2.1, 4, "階段を降りる")
    r.walk(4.1, "開いた格子L1をくぐる")
    r.walk(4.0, "Vine7前")
    r.ff("Vine7", 10.0, dist=1.0, label="ツタへ1本目")
    r.ff("Vine7", 10.0, dist=1.0, label="ツタへ2本目(即育つ)")
    r.lock_wait("Vine7", S7["vineGrow"])
    r.wait(2.2, "ツタを登る(climbSpeed4)")
    r.walk(11.3, "刃ピット3手前へ")
    r.pit_cross("Saw7c", **S7_SAW3, period=S7["sawP3"], x0=83.8, x1=89.8, label="(東向き)")
    r.ff("LockZ7", 10.0, dist=8.2, label="◆種まき: 終錠へ")
    r.walk(8.2, "LockZ7前")
    r.lock_wait("LockZ7", S7["lockZ"])
    r.walk(3.5, "ゴール")


# (stage4まで構成: S7 のreportは封印中)

# ════════════════════════════════════════════════════════════════════
# S8「時計職人の卒業試験」(幅120, RW4, 3層5フェーズ) — gen_stages.py 座標に一致
# F8a[0,24] GateA8 x12.2 Bomb8 x15.2/WallW8 x16.2 Fan8 x20.5
# デッキ[22,44] Sill8 x24 BombF8 x29 LockE8 x33 刃ピットbx38.5
# F8b[24,56] Ham8 x49.5 谷[56,60.5]=RevB8 F8c[60.5,72] 谷[72,80]=Ferry8
# F8d[80,92] Lift8 x86 最上層[88,104] Ball8 x90 Tur8 x102
# 崩れ[104,107.4] T8b[107.4,120] LatticeL8 x110 Button8 x113 出口117
# ════════════════════════════════════════════════════════════════════
S8 = K["s8"]
S8_SAW = dict(bx=38.5, amp=1.0, period=4.0, phase=0.0, pit0=37.9, pit1=39.1)


def s8_route_to_A(r):
    r.walk(3.2, "P8aへ")
    r.hops(1.4, 2, "針山1")
    r.walk(2.6, "P8bへ")
    r.hops(1.4, 2, "針山2")
    r.walk(2.8, "GateA8前")


def s8_noarrow(r):
    s8_route_to_A(r)
    r.gate_pass("GateA8", S8["slamA"])


def s8_rwonly(r):
    s8_route_to_A(r)
    r.rw("GateA8", 4.0, dist=1.5, label="スラムA(#1)", cap=S8["slamA"])
    r.gate_reopen_pass("GateA8", S8["slamA"])
    r.dead = "後戻り矢では爆弾Bomb8を起爆できない→壁W8が壊れず先へ進めない"


def s8_plan(r):
    # ── P1 ──
    s8_route_to_A(r)
    r.rw("GateA8", 10.0, dist=1.5, label="スラムA呼び戻し(#1)", cap=S8["slamA"])
    r.gate_reopen_pass("GateA8", S8["slamA"])
    r.walk(1.0, "安全圏x13.2から")
    r.ff("Bomb8", 5.0, dist=2.0, label="起爆矢(累計5秒で爆発)")
    r.bomb_wait_boom("Bomb8", S8["boomB"])
    r.walk(5.3, "瓦礫を抜けてファン(x20.5)の上へ")
    # ── P2 ──
    r.fan_ride("Fan8", 6.0, dist=1.4, label="サージでデッキ(4.4u)へ")
    # BombF8 は矢起爆式化により自然爆発しなくなった(撃たなければ無害な置き爆弾)
    r.walk(6.5, "デッキを東へ(x28)")
    r.ff("LockE8", 10.0, dist=5.2, label="◆種まき1: 終錠Eへ")
    r.ff("LockE8", 10.0, dist=5.2, label="◆種まき2")
    r.walk(4.2, "LockE8前(x32.2)へ")
    r.lock_wait("LockE8", S8["lockE"])
    r.walk(3.3, "刃ピット手前(x36.3)へ")
    r.pit_cross("SawB8", **S8_SAW, x0=36.3, x1=40.7, label="退避ピットで刃越え")
    r.walk(3.3, "デッキ端(x44)へ")
    r.wait(0.3, "地上へ降りる")
    # ── P3 ──
    r.walk(2.0, "P8cへ")
    r.hops(1.4, 2, "針山3")
    r.walk(2.1, "ハンマー手前へ")
    r.hammer_pass("Ham5", 3.2)
    r.walk(2.5, "P8dへ")
    r.hops(1.4, 2, "針山4")
    r.walk(2.6, "谷の縁(x56)へ")
    r.rw("RevB8", 10.0, dist=2.5, label="上がりきった逆橋を引き戻す(#2)", cap=S8["rev8"])
    r.walk(5.0, "橋を渡る(x60.5)")
    r.walk(11.5, "谷2の縁(x72)へ")
    r.ferry_ride("Ferry8", S8["ferryP"], 8.0, label="(谷2)")
    # ── P4 ──
    r.walk(6.0, "リフト(x86)の射撃位置へ")
    r.ff("Lift8", 10.0, dist=4.5, label="リフトへ1本目")
    r.ff("Lift8", 10.0, dist=4.5, label="リフトへ2本目")
    r.walk(4.5, "乗り込み")
    r.rw("Lift8", 10.0, dist=0.5, label="乗ったまま巻き上げ=最上層へ(#3)")
    r.wait(0.6, "最上層へ移る")
    # ── P5 ──
    r.walk(4.0, "最上層(x90)へ")
    r.walk(11.0, "砲台Tur8の弾間を抜けて崩れ足場手前(x103)へ")
    r.crumble_run(["CrA8", "CrB8"], 4.4, label="(最上層)")
    r.ff("Button8", 2.0, dist=5.6, label="格子越しにボタンを撃つ(矢は格子を素通り)")
    r.walk(9.6, "開いた格子をくぐってゴール")


# (stage4まで構成: S8 のreportは封印中)

print("\n" + "═" * 68)
print("判定:", "ALL OK" if ALL_OK else "NG あり — 数値を調整せよ")
sys.exit(0 if ALL_OK else 1)
