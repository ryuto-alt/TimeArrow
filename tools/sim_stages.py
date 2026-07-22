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

    def shot(self, mode, target, amount, dist=5.0, label=""):
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
            actual = min(amount, self.clock(target))
            self.off[target] = self.off.get(target, 0.0) - actual
            self.timer = max(0.0, self.timer - actual * 0.5)
            self.note(f"RW-{amount:g}(実効{actual:g}, 返金{actual * 0.5:g})→{target} {label}")
        self.arrow_ready = self.real + STUCK_RETURN
        return actual

    def ff(self, target, amount, dist=5.0, label=""):
        return self.shot("ff", target, amount, dist, label)

    def rw(self, target, amount, dist=5.0, label=""):
        return self.shot("rw", target, amount, dist, label)

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
# S1「遅すぎる橋」 15s / RW1 — 幅33: FloorL[0,20] 橋[20,28](降下15s) FloorR[28,33]
# ════════════════════════════════════════════════════════════════════


def s1_noarrow(r):
    r.walk(18.7, "橋の縁まで")
    r.wait(max(0.0, 15.0 - r.clock("Bridge1")), "橋の自然降下待ち")
    r.walk(8.3 + 2.7, "橋を渡ってゴール")


def s1_plan(r):
    r.walk(15.0, "射撃位置x16へ")
    r.ff("Bridge1", 10.0, dist=10.0, label="降下中の橋へフル")
    r.walk(3.7, "橋の縁へ")
    r.wait(max(0.0, 15.0 - r.clock("Bridge1")), "残りの降下待ち")
    r.walk(8.3 + 2.7, "橋を渡ってゴール")


ALL_OK &= report("S1 遅すぎる橋", 15, 1, [
    ("矢なし", s1_noarrow, False),
    ("RWのみ(橋は上がるだけ)", s1_noarrow, False),
    ("想定解", s1_plan, True),
], margin=(1.5, 5.0))

# ════════════════════════════════════════════════════════════════════
# S2「二枚の閉門」 16s / RW2 — 幅28: 針山x4.6-6.3/x9-10.7 GateA x13(閉2.8)
#   針山x16.4-18.1 GateB x21.5(閉6.0) 出口25.8
# ════════════════════════════════════════════════════════════════════


def s2_route_to_A(r):
    r.walk(3.0, "針山1へ")
    r.hops(3.4, 3, "針山1")
    r.walk(1.9)
    r.hops(3.4, 2, "針山2")
    r.walk(1.5, "GateA前")


def s2_noarrow(r):
    s2_route_to_A(r)
    r.gate_pass("GateA", 2.8)


def s2_ffonly(r):
    s2_route_to_A(r)
    r.ff("GateA", 2.0, dist=1.5, label="FFは閉門を進めるだけ")
    r.gate_pass("GateA", 2.8)


def s2_plan(r):
    s2_route_to_A(r)
    r.rw("GateA", 6.0, dist=1.5, label="呼び戻し")
    r.gate_reopen_pass("GateA", 2.8)
    r.walk(2.2)
    r.hops(3.4, 2, "針山3")
    r.walk(2.2, "GateB前")
    r.rw("GateB", 8.0, dist=1.5, label="呼び戻し")
    r.gate_reopen_pass("GateB", 6.0)
    r.walk(4.3, "ゴール")


ALL_OK &= report("S2 二枚の閉門", 16, 2, [
    ("矢なし", s2_noarrow, False),
    ("FFのみ", s2_ffonly, False),
    ("想定解", s2_plan, True),
], margin=(2.0, 14.0))

# ════════════════════════════════════════════════════════════════════
# S3「錠と門」 20s / RW1 — 幅30: 射撃台x7.4-8.6 錠x11.4(開22) 針山x15-18
#   閉門x21.4(閉1.5) 出口26.8
# ════════════════════════════════════════════════════════════════════


def s3_route(r):
    r.walk(6.0, "段差へ")
    r.hops(2.0, 2, "射撃台(段差二段)へ")


def s3_noarrow(r):
    s3_route(r)
    r.lock_wait("Lock3", 22.0)
    r.walk(9.0, "針山区間")
    r.gate_pass("Gate3", 1.5)


def s3_ffonly(r):
    s3_route(r)
    r.ff("Lock3", 10.0, dist=2.8)
    r.ff("Lock3", 10.0, dist=2.8)
    r.lock_wait("Lock3", 22.0)
    r.walk(6.0)
    r.hops(3.0, 2)
    r.gate_pass("Gate3", 1.5)


def s3_rwonly(r):
    s3_route(r)
    r.lock_wait("Lock3", 22.0)
    r.walk(6.0)
    r.hops(3.0, 2)
    r.walk(1.4)
    r.rw("Gate3", 10.0, dist=1.2, label="1発では届かない")
    r.gate_reopen_pass("Gate3", 1.5)


def s3_plan(r):
    s3_route(r)
    r.ff("Lock3", 10.0, dist=2.8, label="錠へ1本目")
    r.ff("Lock3", 10.0, dist=2.8, label="錠へ2本目")
    r.lock_wait("Lock3", 22.0)
    r.walk(2.6)
    r.hops(3.0, 2, "針山")
    r.walk(2.4, "Gate3前")
    r.rw("Gate3", 10.0, dist=1.2, label="閉門を呼び戻す")
    r.gate_reopen_pass("Gate3", 1.5)
    r.walk(5.4, "ゴール")


ALL_OK &= report("S3 錠と門", 20, 1, [
    ("矢なし", s3_noarrow, False),
    ("FFのみ", s3_ffonly, False),
    ("RWのみ", s3_rwonly, False),
    ("想定解", s3_plan, True),
], margin=(1.5, 6.0))

# ════════════════════════════════════════════════════════════════════
# S4「動かせない締切」 23s / RW2 — 幅30: 針山x4-6.4/x8.4-10.4 スラムA x13(閉2.6)
#   錠x15.4(開25) 刃ピットbx19.4[18.8,20.0] 閉門B x24.4(閉15) 出口28.6
# ════════════════════════════════════════════════════════════════════
S4_SAW = dict(bx=19.4, amp=1.0, period=4.0, phase=0.0, pit0=18.8, pit1=20.0)


def s4_route_to_A(r):
    r.walk(2.6, "針山1へ")
    r.hops(3.2, 2, "針山1")
    r.walk(1.6)
    r.hops(2.8, 2, "針山2")
    r.walk(2.0, "スラムA前")


def s4_noarrow(r):
    s4_route_to_A(r)
    r.gate_pass("GateA4", 2.6)


def s4_rwonly(r):
    s4_route_to_A(r)
    r.rw("GateA4", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA4", 2.6)
    r.lock_wait("Lock4", 25.0)
    r.pit_cross("Saw4", **S4_SAW, x0=16.6, x1=22.1)
    r.walk(1.6)
    r.rw("GateB4", 10.0, dist=1.2, label="残1発(上限10で届かない)")
    r.gate_reopen_pass("GateB4", 15.0)


def s4_plan(r):
    s4_route_to_A(r)
    r.rw("GateA4", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA4", 2.6)
    r.walk(1.4, "射撃位置")
    r.ff("Lock4", 10.0, dist=1.5, label="錠へ1本目")
    r.ff("Lock4", 10.0, dist=1.5, label="錠へ2本目")
    r.lock_wait("Lock4", 25.0)
    r.pit_cross("Saw4", **S4_SAW, x0=16.6, x1=22.1, label="退避ピットで刃越え")
    r.walk(1.6, "GateB前")
    r.gate_pass("GateB4", 15.0, "サンドの締切")
    r.walk(4.0, "ゴール")


ALL_OK &= report("S4 動かせない締切", 23, 2, [
    ("矢なし", s4_noarrow, False),
    ("FFのみ", s4_noarrow, False),
    ("RWのみ", s4_rwonly, False),
    ("想定解", s4_plan, True),
], margin=(1.5, 6.0))

# ════════════════════════════════════════════════════════════════════
# S5「時の昇降機」 26s / RW3 — 幅34: 針山x4.2-5.8 リフトx12.5[11,14](自然降下14)
#   デッキ[16,34]y4 スラムx16.6(閉2.6) 大玉x20.5(速0.55) 退避ピット[24,25.2]
#   終錠x30.4(開30) 出口x32.6
# ════════════════════════════════════════════════════════════════════
S5_BALL = dict(bx=20.5, rollT=0.0, speed=0.55)
S5_GOAL = 32.6


def s5_ground(r):
    r.walk(3.2, "針山へ")
    r.hops(1.8, 2, "針山")
    r.walk(2.4, "リフト射撃位置x8")


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
    r.wait(max(0.0, 14.0 - r.clock("Lift5")), "自然降下待ち")
    r.walk(4.5, "乗り込み")
    r.rw("Lift5", 10.0, dist=0.5, label="巻き上げ")
    r.wait(0.6)
    r.walk(2.6, "スラム前")
    r.rw("Gate5", 10.0, dist=1.0, label="1発目(時計が古く開かない)")
    r.gate_reopen_pass("Gate5", 2.6)
    r.rw("Gate5", 10.0, dist=1.0, label="2発目でようやく開く")
    r.gate_reopen_pass("Gate5", 2.6)
    r.goal_alive("Ball5", **S5_BALL, goal_x=S5_GOAL, label="玉に矢が残っていない")


def s5_plan(r):
    s5_ground(r)
    r.ff("Lift5", 10.0, dist=4.5, label="リフトへ1本目")
    r.ff("Lift5", 4.0, dist=4.5, label="リフトへ2本目(時計14で着地)")
    r.walk(4.5, "乗り込み")
    r.rw("Lift5", 10.0, dist=0.5, label="乗ったまま巻き上げ=上昇!")
    r.wait(0.6, "デッキへ移る")
    r.walk(2.6, "スラム前")
    r.rw("Gate5", 10.0, dist=1.0, label="呼び戻し(時計が若く1発)")
    r.gate_reopen_pass("Gate5", 2.6)
    r.walk(7.2, "退避ピットへ")
    r.wait(0.3, "ピットに降りる")
    r.rw("Ball5", 10.0, dist=2.5, label="大玉を呼び戻す(頭上を逆走)")
    r.wait(0.8, "通過待ち")
    r.wait(0.3, "ピットから出る")
    r.walk(5.2, "デッキを右へ")
    r.ball_block_check("Ball5", **S5_BALL, px=30.0, label="先行確認")
    r.ff("Lock5", 10.0, dist=1.5, label="終錠へ1本目")
    r.ff("Lock5", 10.0, dist=1.5, label="終錠へ2本目")
    r.lock_wait("Lock5", 30.0)
    r.goal_alive("Ball5", **S5_BALL, goal_x=S5_GOAL, label="レース勝利")
    r.walk(2.2, "ゴール")


ALL_OK &= report("S5 時の昇降機", 26, 3, [
    ("矢なし", s5_noarrow, False),
    ("FFのみ", s5_ffonly, False),
    ("RWのみ(スラムに2発必要で玉に届かない)", s5_rwonly, False),
    ("想定解", s5_plan, True),
], margin=(1.5, 10.0))

# ════════════════════════════════════════════════════════════════════
# S6「導火線」 30s / RW2 — 幅34: 針山x4.4-7/x9.4-11.6 スラムA x13.6(閉2.8)
#   爆弾x17.6+壁x18.6(自然24) 閉門C x21.6(閉12) 針山x23.6-26.2 錠x27.6(開21) 出口32
# ════════════════════════════════════════════════════════════════════


def s6_route_to_A(r):
    r.walk(3.0, "針山1へ")
    r.hops(3.2, 2, "針山1")
    r.walk(1.8)
    r.hops(2.8, 2, "針山2")
    r.walk(2.0, "スラムA前")


def s6_noarrow(r):
    s6_route_to_A(r)
    r.gate_pass("GateA6", 2.8)


def s6_rwonly(r):
    s6_route_to_A(r)
    r.rw("GateA6", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA6", 2.8)
    r.walk(2.2, "爆弾の安全圏x15.8で待機")
    r.bomb_wait_boom("BombB6", 24.0)
    r.walk(4.2, "瓦礫を抜けC前へ")
    r.rw("GateC6", 10.0, dist=1.2, label="1発目(届かない)")
    r.gate_reopen_pass("GateC6", 12.0)


def s6_plan(r):
    s6_route_to_A(r)
    r.rw("GateA6", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA6", 2.8)
    r.walk(2.2, "安全圏x15.8から狙う")
    r.ff("BombB6", 10.0, dist=1.9, label="導火線を1本目")
    r.ff("BombB6", 10.0, dist=1.9, label="2本目→ほぼ即起爆")
    r.wait(0.5, "爆発")
    r.walk(4.2, "瓦礫を抜ける")
    r.gate_pass("GateC6", 12.0, "まだ開いている")
    r.walk(2.4)
    r.hops(2.6, 2, "針山3")
    r.walk(1.6, "錠前")
    r.ff("Lock6", 10.0, dist=1.5, label="錠へ(半分だけ前借り)")
    r.lock_wait("Lock6", 21.0)
    r.walk(4.4, "ゴール")


ALL_OK &= report("S6 導火線", 30, 2, [
    ("矢なし", s6_noarrow, False),
    ("FFのみ", s6_noarrow, False),
    ("RWのみ", s6_rwonly, False),
    ("想定解", s6_plan, True),
], margin=(1.5, 8.0))

# ════════════════════════════════════════════════════════════════════
# S7「時計塔の往復」 36s / RW3 — 幅31: 塔x0.5(ボタン) 針山x3.4-5.6/x7.2-9.4
#   スラムA x11.4(閉2.3) 格子x13.3 出口x14.2(袋小路) 壁x15.4 階段x27.7-29.8
#   デッキ[2.6,26.4]y4.4 刃ピットbx16[15.2,16.8] 錠D x4.4(開26)
# ════════════════════════════════════════════════════════════════════
S7_SAW = dict(bx=16.0, amp=1.2, period=4.0, phase=0.0, pit0=16.8, pit1=15.2)


def s7_route_to_A(r):
    r.walk(2.0, "針山1へ")
    r.hops(3.2, 2, "針山1")
    r.walk(1.6)
    r.hops(3.2, 2, "針山2")
    r.walk(2.0, "スラムA前")


def s7_noarrow(r):
    s7_route_to_A(r)
    r.gate_pass("GateA7", 2.3)


def s7_rwonly(r):
    s7_route_to_A(r)
    r.rw("GateA7", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA7", 2.3)
    r.walk(17.0, "地上を東へ")
    r.hops(2.8, 4, "階段でデッキへ")
    r.walk(10.5, "デッキを西へ")
    r.pit_cross("Saw7", **S7_SAW, x0=18.5, x1=13.6, label="(西向き)")
    r.walk(9.2, "錠D前")
    r.lock_wait("LockD7", 26.0)
    r.dead = "ボタンはFF矢でしか押せない → 格子が開かず出口に入れない"


def s7_plan(r):
    s7_route_to_A(r)
    r.rw("GateA7", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA7", 2.3)
    r.walk(17.0, "地上を東へ(頭上のデッキと塔を観察)")
    r.hops(2.8, 4, "階段でデッキへ")
    r.walk(10.5, "デッキを西へ")
    r.pit_cross("Saw7", **S7_SAW, x0=18.5, x1=13.6, label="(西向き)")
    r.walk(9.2, "錠D前")
    r.ff("LockD7", 10.0, dist=1.5, label="錠Dへ1本目")
    r.ff("LockD7", 8.0, dist=1.5, label="錠Dへ2本目(待つより得)")
    r.lock_wait("LockD7", 26.0)
    r.walk(0.7, "デッキ左端")
    r.ff("ButtonB7", 2.0, dist=3.2, label="塔上のボタンへFF矢→格子が開く")
    r.walk(0.5, "縁へ")
    r.wait(0.5, "飛び降り")
    r.walk(11.1, "地上を東へ、開いた格子x13.3をくぐる")
    r.walk(0.9, "袋小路の出口へ")


ALL_OK &= report("S7 時計塔の往復", 36, 3, [
    ("矢なし", s7_noarrow, False),
    ("FFのみ", s7_noarrow, False),
    ("RWのみ", s7_rwonly, False),
    ("想定解", s7_plan, True),
], margin=(2.0, 10.0))

# ════════════════════════════════════════════════════════════════════
# S8「時計職人の卒業試験」 38s / RW4 — 幅36: 針山x4-6.2/x8.2-10.2 スラムA x12.2(閉2.6)
#   爆弾x15.2+壁x16.2(自然26) 閉門C x18.6(閉13) 階段x20.6-22 デッキ[22.6,36]y4.4
#   スラムD x24(閉10.5) 種まき射点x30 爆弾F x31(自然22,待機圏を薙ぐ) 終錠x32.4(開36)
#   銀行ノコx19,y6.6 出口x33.4
# ════════════════════════════════════════════════════════════════════


def s8_route_to_A(r):
    r.walk(2.6, "針山1へ")
    r.hops(2.8, 2, "針山1")
    r.walk(1.4)
    r.hops(2.6, 2, "針山2")
    r.walk(1.4, "スラムA前")


def s8_noarrow(r):
    s8_route_to_A(r)
    r.gate_pass("GateA8", 2.6)


def s8_rwonly(r):
    s8_route_to_A(r)
    r.rw("GateA8", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA8", 2.6)
    r.walk(1.0, "安全圏で待機")
    r.bomb_wait_boom("BombB8", 26.0)
    r.walk(3.4, "瓦礫を抜けC前")
    r.rw("GateC8", 10.0, dist=1.2, label="C 1発目")
    r.gate_reopen_pass("GateC8", 13.0)
    r.rw("GateC8", 10.0, dist=1.2, label="C 2発目")
    r.gate_reopen_pass("GateC8", 13.0)
    r.walk(2.0)
    r.hops(2.0, 4, "階段→デッキ")
    r.walk(1.4, "スラムD前")
    r.rw("GateD8", 10.0, dist=1.2, label="D 残り1発(時計-10でもまだ閉)")
    r.gate_reopen_pass("GateD8", 10.5)


def s8_plan(r):
    s8_route_to_A(r)
    r.rw("GateA8", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA8", 2.6)
    r.walk(1.0, "安全圏x13.2から")
    r.ff("BombB8", 10.0, dist=2.0, label="導火線1本目")
    r.ff("BombB8", 10.0, dist=2.0, label="2本目(時計まだ25前後)")
    r.ff("BombB8", 4.0, dist=2.0, label="3本目→起爆")
    r.wait(0.5, "爆発")
    r.walk(3.4, "瓦礫を抜ける")
    r.gate_pass("GateC8", 13.0, "サンドの締切")
    r.walk(2.0, "階段へ")
    r.hops(2.0, 4, "階段→デッキ")
    r.walk(1.4, "スラムD前")
    r.rw("GateD8", 10.0, dist=1.2, label="D呼び戻し(時計が若く1発)")
    r.gate_reopen_pass("GateD8", 10.5)
    r.walk(6.0, "種まき射点x30へ(爆弾Fの手前)")
    r.ff("LockE8", 10.0, dist=2.6, label="◆種まき1: 終錠へ")
    r.ff("LockE8", 10.0, dist=2.6, label="◆種まき2: 爆弾Fが吹く前に開くように")
    r.rw("BankSaw8", 10.0, dist=8.0, label="◆銀行: 空転ノコへ返金")
    r.walk(1.6, "錠前へ")
    r.lock_wait("LockE8", 36.0)
    if r.clock("BombF8") >= 22.0:
        r.dead = r.dead or f"爆弾F爆発時に待機圏内(実{r.real:.1f} >= 22)"
    r.note(f"爆弾Fまで残り{22.0 - r.clock('BombF8'):.1f}s で錠を通過")
    r.walk(1.0, "ゴール")


def s8_single_seed(r):
    s8_route_to_A(r)
    r.rw("GateA8", 4.0, dist=1.5)
    r.gate_reopen_pass("GateA8", 2.6)
    r.walk(1.0)
    r.ff("BombB8", 10.0, dist=2.0)
    r.ff("BombB8", 10.0, dist=2.0)
    r.ff("BombB8", 4.0, dist=2.0)
    r.wait(0.5)
    r.walk(3.4)
    r.gate_pass("GateC8", 13.0)
    r.walk(2.0)
    r.hops(2.0, 4)
    r.walk(1.4)
    r.rw("GateD8", 10.0, dist=1.2)
    r.gate_reopen_pass("GateD8", 10.5)
    r.walk(6.0)
    r.ff("LockE8", 10.0, dist=2.6, label="種まき1発のみ")
    r.walk(1.6)
    r.lock_wait("LockE8", 36.0)
    if r.clock("BombF8") >= 22.0:
        r.dead = r.dead or f"爆弾Fが待機中に爆発(実{r.real:.1f} >= 22)"
    r.walk(1.0)


ALL_OK &= report("S8 時計職人の卒業試験", 38, 4, [
    ("矢なし", s8_noarrow, False),
    ("FFのみ", s8_noarrow, False),
    ("RWのみ", s8_rwonly, False),
    ("種まき1発(爆弾Fに焼かれる)", s8_single_seed, False),
    ("想定解", s8_plan, True),
], margin=(2.0, 10.0))

print("\n" + "═" * 68)
print("判定:", "ALL OK" if ALL_OK else "NG あり — 数値を調整せよ")
