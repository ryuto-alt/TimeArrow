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

    def clock(self, name):
        return max(0.0, self.real + self.off.get(name, 0.0))

    def note(self, msg):
        self.log.append(f"  t={self.timer:5.1f}/実{self.real:5.1f}  {msg}")

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
    def lock_wait(self, name, openT, label=""):
        c = self.clock(name)
        if c < openT:
            self.advance(openT - c)
            self.note(f"錠{name} 開待ち {openT - c:.1f}s {label}")
        self.advance(0.9)
        self.note(f"錠{name} を通過")

    def gate_pass(self, name, closeT, label=""):
        c = self.clock(name)
        if c >= closeT:
            self.dead = self.dead or f"閉門{name}済み(時計{c:.1f} >= 閉{closeT}) {label}"
        else:
            self.note(f"閉門{name} 通過 (時計{c:.1f} < {closeT}, 余裕{closeT - c:.1f}s) {label}")
        self.advance(0.2)

    def gate_reopen_pass(self, name, closeT, label=""):
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
        c = self.clock(name)
        if c < boomT:
            self.advance(boomT - c)
            self.note(f"爆弾{name} 自然爆発待ち {boomT - c:.1f}s {label}")
        self.advance(0.3)

    def finish(self):
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
            print(f" {'✓' if good else '✗✗'} {label}: {v}"
                  + ("" if good else f"  ← マージン帯{margin}外"))
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
    r.hops(1.6, 2, "針山1")
    r.walk(2.6, "P2bへ")
    r.hops(1.6, 2, "針山2")
    r.walk(2.4, "GateA前")


def s2_noarrow(r):
    s2_route_to_A(r)
    r.gate_pass("GateA", S2["closeA"])


def s2_ffonly(r):
    s2_route_to_A(r)
    r.ff("GateA", 2.0, dist=1.5, label="FFは閉門を進めるだけ")
    r.gate_pass("GateA", S2["closeA"])


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
    r.hops(1.6, 2, "針山3")
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
# S3「三つの錠の取引」(幅58, RW3) — gen_stages.py 座標に一致
# StepA3 x6.6/StepB3 x7.8(射撃台) Lock1 x10.6 Vine1 x13.5(育ち済) P3a[16,17.7]
# GateS1 x20.5(スラム1) P3b[23.5,25.2] GateS2 x28.5(スラム2) Lock2 x38
# (x22-28で種まき) P3c[41.5,43.2] GateZ x46.5(サンド) 出口54
# ════════════════════════════════════════════════════════════════════
S3 = K["s3"]


def s3_route_to_shot(r):
    r.walk(5.8, "段差へ")
    r.hops(1.2, 2, "射撃台(段差二段)へ")


def s3_route_S1(r):
    r.walk(5.7, "Vine1経由でP3aへ")
    r.hops(1.7, 2, "針山1")
    r.walk(2.8, "GateS1前")


def s3_route_S2(r):
    r.walk(3.0, "P3bへ")
    r.hops(1.7, 2, "針山2")
    r.walk(3.3, "GateS2前")


def s3_noarrow(r):
    s3_route_to_shot(r)
    r.lock_wait("Lock1", S3["lock1"])
    s3_route_S1(r)
    r.gate_pass("GateS1", S3["slam1"])


def s3_ffonly(r):
    s3_route_to_shot(r)
    r.ff("Lock1", 10.0, dist=2.8)
    r.ff("Lock1", 10.0, dist=2.8)
    r.lock_wait("Lock1", S3["lock1"])
    s3_route_S1(r)
    r.ff("GateS1", 2.0, dist=1.5, label="FFは閉門を進めるだけ")
    r.gate_pass("GateS1", S3["slam1"])


def s3_rwonly(r):
    # FFなしなのでLock1もLock2も自然開通まで丸ごと待つしかない
    s3_route_to_shot(r)
    r.lock_wait("Lock1", S3["lock1"])
    s3_route_S1(r)
    r.rw("GateS1", 4.0, dist=1.5, label="スラム1(#1)", cap=S3["slam1"])
    r.gate_reopen_pass("GateS1", S3["slam1"])
    s3_route_S2(r)
    r.rw("GateS2", 4.0, dist=1.5, label="スラム2(#2)", cap=S3["slam2"])
    r.gate_reopen_pass("GateS2", S3["slam2"])
    r.walk(9.5, "Lock2前")
    r.lock_wait("Lock2", S3["lock2"], "種まき無しなので自然開通まで待つ")
    r.walk(3.5, "P3cへ")
    r.hops(1.7, 2, "針山3")
    r.walk(3.3, "GateZ前")
    r.rw("GateZ", 4.0, dist=1.2, label="サンド(#3=予算オーバー)", cap=S3["closeZ"])
    r.gate_reopen_pass("GateZ", S3["closeZ"])
    r.rw("GateZ", 10.0, dist=1.2, label="サンド(#4, 予算オーバー)")
    r.gate_reopen_pass("GateZ", S3["closeZ"])


def s3_plan(r):
    s3_route_to_shot(r)
    r.ff("Lock1", 10.0, dist=2.8, label="錠1へ1本目")
    r.ff("Lock1", 10.0, dist=2.8, label="錠1へ2本目")
    r.lock_wait("Lock1", S3["lock1"])
    s3_route_S1(r)
    r.rw("GateS1", 10.0, dist=1.5, label="スラム1を呼び戻す")
    r.gate_reopen_pass("GateS1", S3["slam1"])
    r.walk(3.0, "P3bの手前(x23.5)で錠2へ種まき")
    r.ff("Lock2", 10.0, dist=14.0, label="◆種まき1: 錠2へ")
    r.ff("Lock2", 10.0, dist=14.0, label="◆種まき2: 自然開通を待たず済むように")
    r.hops(1.7, 2, "針山2")
    r.walk(3.3, "GateS2前")
    r.rw("GateS2", 10.0, dist=1.5, label="スラム2を呼び戻す", cap=S3["slam2"])
    r.gate_reopen_pass("GateS2", S3["slam2"])
    r.walk(9.5, "Lock2前")
    r.lock_wait("Lock2", S3["lock2"], "種まき済みなのでほぼ待たずに開く")
    r.walk(3.5, "P3cへ")
    r.hops(1.7, 2, "針山3")
    r.walk(3.3, "GateZ前")
    r.gate_pass("GateZ", S3["closeZ"], "種まき経路は間に合う")
    r.walk(7.5, "ゴール")


ALL_OK &= report("S3 三つの錠の取引", S3["limit"], S3["rw"], [
    ("矢なし", s3_noarrow, False),
    ("FFのみ", s3_ffonly, False),
    ("RWのみ", s3_rwonly, False),
    ("想定解", s3_plan, True),
], margin=(2.0, 10.0))

# ════════════════════════════════════════════════════════════════════
# S4「動かせない締切+動く壁」(幅64, RW3) — gen_stages.py 座標に一致
# P4a[4,5.7] P4b[8.8,10.4] GateA4 x13.0(スラム) Lock4 x15.4 刃ピットbx19.4
# GateB4 x24.4(サンド) CW4 x37(動く壁) P4c[55,56.7] GateZ4 x59.5(サンド2) 出口62.5
# ════════════════════════════════════════════════════════════════════
S4 = K["s4"]
S4_SAW = dict(bx=19.4, amp=1.0, period=4.0, phase=0.0, pit0=18.8, pit1=20.0)


def s4_route_to_A(r):
    r.walk(3.2, "P4aへ")
    r.hops(1.7, 2, "針山1")
    r.walk(3.1, "P4bへ")
    r.hops(1.6, 2, "針山2")
    r.walk(2.6, "GateA4前")


def s4_noarrow(r):
    s4_route_to_A(r)
    r.gate_pass("GateA4", S4["slamA"])


def s4_rwonly(r):
    s4_route_to_A(r)
    r.rw("GateA4", 4.0, dist=1.5, label="スラムA", cap=S4["slamA"])
    r.gate_reopen_pass("GateA4", S4["slamA"])
    r.walk(2.4, "Lock4前")
    r.lock_wait("Lock4", S4["lockOpen"])
    r.pit_cross("Saw4", **S4_SAW, x0=16.6, x1=22.1)
    r.walk(2.3, "GateB4前")
    r.rw("GateB4", 4.0, dist=1.2, label="B(#2, 閉門は止まるので1発で開く)", cap=S4["closeB"])
    r.gate_reopen_pass("GateB4", S4["closeB"])
    r.walk(12.0, "動く壁が止まるのを待ちつつ東へ")
    r.wait(4.0, "壁の通過待ち(自然)")
    r.walk(10.0, "GateZ4前")
    r.rw("GateZ4", 4.0, dist=1.2, label="Z(#3=予算オーバー)", cap=S4["closeZ"])
    r.gate_reopen_pass("GateZ4", S4["closeZ"])


def s4_plan(r):
    s4_route_to_A(r)
    r.rw("GateA4", 4.0, dist=1.5, label="スラムA呼び戻し", cap=S4["slamA"])
    r.gate_reopen_pass("GateA4", S4["slamA"])
    r.walk(2.4, "射撃位置")
    r.ff("Lock4", 10.0, dist=1.5, label="錠へ1本目")
    r.ff("Lock4", 10.0, dist=1.5, label="錠へ2本目")
    r.lock_wait("Lock4", S4["lockOpen"])
    r.pit_cross("Saw4", **S4_SAW, x0=16.6, x1=22.1, label="退避ピットで刃越え")
    r.walk(2.3, "GateB4前")
    r.gate_pass("GateB4", S4["closeB"], "サンドの締切")
    r.walk(12.6, "CW4前")
    r.ff("CW4", 2.0, dist=1.5, label="動く壁をゴースト通過")
    r.wait(0.4, "ゴースト通過中")
    r.walk(18.0, "P4cへ")
    r.hops(1.7, 2, "針山3")
    r.walk(2.8, "GateZ4前")
    r.gate_pass("GateZ4", S4["closeZ"], "壁が止まる前に通過")
    r.walk(3.0, "ゴール")


ALL_OK &= report("S4 動かせない締切+動く壁", S4["limit"], S4["rw"], [
    ("矢なし", s4_noarrow, False),
    ("FFのみ", s4_noarrow, False),
    ("RWのみ", s4_rwonly, False),
    ("想定解", s4_plan, True),
], margin=(2.0, 10.0))

# ════════════════════════════════════════════════════════════════════
# S5「時の昇降機・改」(幅88, RW4, 3層) — gen_stages.py 座標に一致
# StepA5 x4.2/N5 x4.9/StepB5 x5.6 Lift5 x12.5 デッキ[16,52] Gate5 x17.2
# Ball5 x19.5 PitR1F x28.6 LockD5 x46 Vine5 x61.2 最上層[62,88] Ferry5 x72
# GateY5 x76.5 LockZ5 x82 出口85.5
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
    r.walk(11.4, "退避ピット1へ")
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
    r.walk(14.8, "GateY5前(種まき無し)")
    r.rw("GateY5", 10.0, dist=1.0, label="最後の1発(#4)")
    r.gate_reopen_pass("GateY5", S5["closeY"])


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
    r.walk(11.4, "退避ピット1へ")
    r.wait(0.3, "ピットに降りる")
    r.rw("Ball5", 10.0, dist=2.5, label="大玉を呼び戻す(頭上を逆走, #3)")
    r.wait(0.8, "通過待ち")
    r.wait(0.3, "ピットから出る")
    r.walk(3.4, "種まき位置(x32)へ")
    r.ff("LockD5", 10.0, dist=14.0, label="◆種まき: 終錠へ")
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
    r.wait(S5["ferryP"] / 2, "フェリーの間合い")
    r.walk(2.2, "フェリーで渡る(振れ幅2.2)")
    r.walk(2.5, "GateY5前")
    r.gate_pass("GateY5", S5["closeY"], "サンドの締切")
    r.walk(5.5, "LockZ5前")
    r.lock_wait("LockZ5", S5["lockZ"])
    r.goal_alive("Ball5", **S5_BALL, goal_x=S5_GOAL, label="レース勝利")
    r.walk(3.5, "ゴール")


ALL_OK &= report("S5 時の昇降機・改", S5["limit"], S5["rw"], [
    ("矢なし", s5_noarrow, False),
    ("FFのみ", s5_ffonly, False),
    ("RWのみ", s5_rwonly, False),
    ("想定解", s5_plan, True),
], margin=(2.0, 12.0))

# ════════════════════════════════════════════════════════════════════
# S6「二本の導火線」(幅96, RW3, 2層) — gen_stages.py 座標に一致
# P6a[4.4,6.1] P6b[9.4,11.0] GateA6 x13.6 Bomb6 x17.6/WallW6 x18.6
# GateC6 x21.6 階段25.4-27.5 レッジ[28.5,64] Bomb62 x44/WallW62 x45.4
# GateE6 x52 P6c[68,69.7] P6d[73,74.7] LockZ6 x80 出口92
# ════════════════════════════════════════════════════════════════════
S6 = K["s6"]


def s6_route_to_A(r):
    r.walk(3.6, "P6aへ")
    r.hops(1.7, 2, "針山1")
    r.walk(3.3, "P6bへ")
    r.hops(1.6, 2, "針山2")
    r.walk(2.6, "GateA6前")


def s6_noarrow(r):
    s6_route_to_A(r)
    r.gate_pass("GateA6", S6["slamA"])


def s6_rwonly(r):
    s6_route_to_A(r)
    r.rw("GateA6", 10.0, dist=1.5, label="スラムA(#1)")
    r.gate_reopen_pass("GateA6", S6["slamA"])
    r.walk(2.2, "爆弾の安全圏x15.8")
    r.bomb_wait_boom("Bomb6", S6["boom1"], "自然爆発まで待つ(長い)")
    r.walk(5.8, "瓦礫を抜けC前へ")
    r.rw("GateC6", 10.0, dist=1.2, label="サンド(#2)")
    r.rw("GateC6", 10.0, dist=1.2, label="サンド(#3, もう予算がない)")
    r.gate_reopen_pass("GateC6", S6["closeC"])
    r.walk(6.9, "階段でレッジへ")
    r.walk(13.5, "レッジを進む")
    r.bomb_wait_boom("Bomb62", S6["boom2"], "自然爆発まで待つ(長い)")
    r.walk(10.0, "瓦礫を抜けE前へ")
    r.rw("GateE6", 10.0, dist=1.2, label="スラム(#4, 予算オーバー)")
    r.gate_reopen_pass("GateE6", S6["closeE"])


def s6_plan(r):
    s6_route_to_A(r)
    r.rw("GateA6", 10.0, dist=1.5, label="スラムA呼び戻し(#1)")
    r.gate_reopen_pass("GateA6", S6["slamA"])
    r.walk(2.2, "安全圏x15.8から狙う")
    r.ff("Bomb6", 10.0, dist=1.9, label="導火線1本目")
    r.ff("Bomb6", 10.0, dist=1.9, label="2本目→ほぼ即起爆")
    r.bomb_wait_boom("Bomb6", S6["boom1"])
    r.walk(5.8, "瓦礫を抜けてGateC6前へ")
    r.gate_pass("GateC6", S6["closeC"], "まだ開いている")
    r.walk(6.9, "階段でレッジへ")
    r.walk(13.5, "レッジを進む(x42へ)")
    r.ff("Bomb62", 10.0, dist=2.0, label="導火線2の1本目(爆風外から)")
    r.ff("Bomb62", 10.0, dist=2.0, label="2本目→起爆")
    r.bomb_wait_boom("Bomb62", S6["boom2"])
    r.walk(10.0, "瓦礫を抜けてGateE6前へ")
    r.rw("GateE6", 10.0, dist=1.2, label="スラムを呼び戻す(#2)")
    r.gate_reopen_pass("GateE6", S6["closeE"])
    r.walk(12.0, "レッジ端64へ")
    r.wait(0.3, "地上へ降りる")
    r.walk(2.0, "種まき位置(x66)へ")
    r.ff("LockZ6", 10.0, dist=14.0, label="◆種まき: 終錠へ(水平)")
    r.walk(2.0, "P6cへ")
    r.hops(1.7, 2, "針山3")
    r.walk(3.3, "P6dへ")
    r.hops(1.7, 2, "針山4")
    r.walk(5.3, "LockZ6前")
    r.lock_wait("LockZ6", S6["lockZ"])
    r.walk(12.0, "ゴール")


ALL_OK &= report("S6 二本の導火線", S6["limit"], S6["rw"], [
    ("矢なし", s6_noarrow, False),
    ("FFのみ", s6_noarrow, False),
    ("RWのみ", s6_rwonly, False),
    ("想定解", s6_plan, True),
], margin=(1.5, 8.0))

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
    r.walk(2.6, "GateA7前")


def s7_noarrow(r):
    s7_route_to_A(r)
    r.gate_pass("GateA7", S7["slamA"])


def s7_rwonly(r):
    s7_route_to_A(r)
    r.rw("GateA7", 10.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA7", S7["slamA"])
    r.walk(53.0, "地上を東へ(階段まで)")
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
    r.rw("GateA7", 10.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA7", S7["slamA"])
    r.walk(53.0, "地上を東へ(階段まで)")
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


ALL_OK &= report("S7 時計塔大回廊", S7["limit"], S7["rw"], [
    ("矢なし", s7_noarrow, False),
    ("FFのみ", s7_noarrow, False),
    ("RWのみ", s7_rwonly, False),
    ("想定解", s7_plan, True),
], margin=(3.0, 14.0))

# ════════════════════════════════════════════════════════════════════
# S8「時計職人の卒業試験・大」(幅120, RW5, 3層4フェーズ) — gen_stages.py 座標に一致
# P8a[4,5.4] P8b[8,9.4] GateA8 x12.2 Bomb8 x15.2/WallW8 x16.2 GateC8 x18.6
# 階段20.6-22 デッキ[22.6,40] GateD8 x24 BombF8 x31 LockE8 x33.5 SawB8 x37.8
# P8c[46,47.4] P8d[52,53.4] GateG8 x58 Lift8 x68 最上層[70,120] Ball8 x76
# PitT8F x86.6 GateY8 x94 LockZ8 x110 出口116
# ════════════════════════════════════════════════════════════════════
S8 = K["s8"]
S8_BALL = dict(bx=76.0, rollT=S8["ballRoll"], speed=S8["ballSpeed"])
S8_GOAL = 116.0


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
    r.rw("GateA8", 10.0, dist=1.5, label="スラムA(#1)")
    r.gate_reopen_pass("GateA8", S8["slamA"])
    r.walk(1.0, "安全圏で待機")
    r.bomb_wait_boom("Bomb8", S8["boomB"], "自然爆発まで待つ(長い)")
    r.walk(5.4, "瓦礫を抜けC前へ")
    r.rw("GateC8", 4.0, dist=1.2, label="C(#2)", cap=S8["closeC"])
    r.gate_reopen_pass("GateC8", S8["closeC"])
    r.walk(2.0, "階段へ")
    r.hops(1.4, 3, "階段→デッキ")
    r.walk(2.0, "GateD前")
    r.rw("GateD8", 4.0, dist=1.2, label="D(#3)", cap=S8["slamD"])
    r.gate_reopen_pass("GateD8", S8["slamD"])
    r.walk(7.8, "LockE8圏内へ")
    r.lock_wait("LockE8", S8["lockE"], "種まき無しで自然開通待ち")
    if r.clock("BombF8") >= S8["boomF"]:
        r.dead = r.dead or "爆弾Fが自然爆発するまで待つ間に爆死"
    r.walk(6.5, "降りてGateG8前")
    r.rw("GateG8", 4.0, dist=1.2, label="G(#4)", cap=S8["closeG"])
    r.gate_reopen_pass("GateG8", S8["closeG"])
    r.walk(10.0, "リフト前")
    r.wait(max(0.0, S8["lift"] - r.clock("Lift8")) + 1.0, "リフト自然降下+乗り込み")
    r.rw("Lift8", 10.0, dist=0.5, label="巻き上げ(#5)")
    r.wait(0.8, "最上層へ")
    r.walk(8.0, "GateY8前")
    r.rw("GateY8", 4.0, dist=1.0, label="Y(#6=予算オーバー)", cap=S8["closeY"])
    r.gate_reopen_pass("GateY8", S8["closeY"])


def s8_plan(r):
    s8_route_to_A(r)
    r.rw("GateA8", 10.0, dist=1.5, label="スラムA呼び戻し(#1)")
    r.gate_reopen_pass("GateA8", S8["slamA"])
    r.walk(1.0, "安全圏x13.2から")
    r.ff("Bomb8", 10.0, dist=2.0, label="導火線1本目")
    r.ff("Bomb8", 10.0, dist=2.0, label="2本目")
    r.ff("Bomb8", 4.0, dist=2.0, label="3本目→起爆")
    r.bomb_wait_boom("Bomb8", S8["boomB"])
    r.walk(5.4, "瓦礫を抜けてGateC8前へ")
    r.gate_pass("GateC8", S8["closeC"], "サンドの締切")
    r.walk(2.0, "階段へ")
    r.hops(1.4, 3, "階段→デッキ")
    r.walk(2.0, "GateD8前")
    r.rw("GateD8", 10.0, dist=1.2, label="D呼び戻し(#2)")
    r.gate_reopen_pass("GateD8", S8["slamD"])
    r.walk(7.8, "爆弾Fの圏内x31.8から種まき")
    r.ff("LockE8", 10.0, dist=1.7, label="◆種まき1: 終錠Eへ")
    r.ff("LockE8", 10.0, dist=1.7, label="◆種まき2: 爆発前に開けるように")
    r.walk(1.7, "LockE8前")
    r.lock_wait("LockE8", S8["lockE"])
    if r.clock("BombF8") >= S8["boomF"]:
        r.dead = r.dead or "爆弾Fの爆風内に留まってしまった"
    r.walk(4.3, "刃ピット(銀行,任意)を過ぎて")
    r.wait(0.3, "地上へ降りる")
    r.walk(8.2, "P8cへ")
    r.hops(1.4, 2, "針山3")
    r.walk(4.6, "P8dへ")
    r.hops(1.4, 2, "針山4")
    r.walk(4.6, "GateG8前")
    r.gate_pass("GateG8", S8["closeG"], "スプリント")
    r.walk(10.0, "Lift8前")
    r.ff("Lift8", 10.0, dist=4.5, label="リフトへ1本目")
    r.ff("Lift8", 10.0, dist=4.5, label="リフトへ2本目")
    r.walk(4.5, "乗り込み")
    r.rw("Lift8", 10.0, dist=0.5, label="乗ったまま巻き上げ=最上層へ(#3)")
    r.wait(0.6, "最上層へ移る")
    r.walk(8.0, "Ball8を横目に先行(x76付近)")
    r.walk(18.0, "退避ピットを過ぎてGateY8前へ")
    r.rw("GateY8", 10.0, dist=1.0, label="スラムを呼び戻す(#4)")
    r.gate_reopen_pass("GateY8", S8["closeY"])
    r.walk(2.0, "種まき位置(x96)へ")
    r.ff("LockZ8", 10.0, dist=14.0, label="◆種まき1: 終錠Zへ(二重)")
    r.ff("LockZ8", 10.0, dist=14.0, label="◆種まき2")
    r.walk(14.0, "LockZ8前")
    r.lock_wait("LockZ8", S8["lockZ"])
    r.goal_alive("Ball8", **S8_BALL, goal_x=S8_GOAL, label="ゴール死守")
    r.walk(6.0, "ゴール")


ALL_OK &= report("S8 時計職人の卒業試験・大", S8["limit"], S8["rw"], [
    ("矢なし", s8_noarrow, False),
    ("FFのみ", s8_noarrow, False),
    ("RWのみ", s8_rwonly, False),
    ("想定解", s8_plan, True),
], margin=(3.0, 12.0))

print("\n" + "═" * 68)
print("判定:", "ALL OK" if ALL_OK else "NG あり — 数値を調整せよ")
