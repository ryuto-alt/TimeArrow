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
# S1「遅すぎる橋」 15s / RW1 — FF入門: 橋(降下16s)は自然には間に合わない
# ════════════════════════════════════════════════════════════════════


def s1_noarrow(r):
    r.walk(8.7, "橋の縁まで")
    r.wait(16.0 - r.clock("Bridge1"), "橋の自然降下待ち")
    r.walk(5.4, "橋を渡ってゴール")


def s1_plan(r):
    r.walk(7.0, "射撃位置x8へ")
    r.ff("Bridge1", 10.0, dist=6.0, label="降下中の橋へフル")
    r.walk(1.7, "橋の縁へ")
    r.wait(max(0.0, 16.0 - r.clock("Bridge1")), "残りの降下待ち")
    r.walk(5.4, "橋を渡ってゴール")


ALL_OK &= report("S1 遅すぎる橋", 15, 1, [
    ("矢なし", s1_noarrow, False),
    ("RWのみ(橋は上がるだけ)", s1_noarrow, False),
    ("想定解", s1_plan, True),
], margin=(1.5, 5.0))

# ════════════════════════════════════════════════════════════════════
# S2「二枚の閉門」 16s / RW2 — RW入門: 目の前でガシャン→呼び戻す×2
# 針山2枚で最速到達2.5 > 閉A2.0。B(x14)は閉4.5 < 到達5.0
# ════════════════════════════════════════════════════════════════════


def s2_route_to_A(r):
    r.walk(1.4, "針山1へ")
    r.hops(3.2, 3, "針山1")
    r.walk(0.8)
    r.hops(2.6, 2, "針山2")
    r.walk(0.8, "GateA前")


def s2_noarrow(r):
    s2_route_to_A(r)
    r.gate_pass("GateA", 2.0)


def s2_ffonly(r):
    s2_route_to_A(r)
    r.ff("GateA", 2.0, dist=1.5, label="FFは閉門を進めるだけ")
    r.gate_pass("GateA", 2.0)


def s2_plan(r):
    s2_route_to_A(r)
    r.rw("GateA", 6.0, dist=1.5, label="呼び戻し")
    r.gate_reopen_pass("GateA", 2.0)
    r.hops(2.4, 2, "針山3")
    r.walk(1.6, "GateB前")
    r.rw("GateB", 6.0, dist=1.5, label="呼び戻し")
    r.gate_reopen_pass("GateB", 4.5)
    r.walk(1.7, "ゴール")


ALL_OK &= report("S2 二枚の閉門", 16, 2, [
    ("矢なし", s2_noarrow, False),
    ("FFのみ", s2_ffonly, False),
    ("想定解", s2_plan, True),
], margin=(2.0, 14.0))

# ════════════════════════════════════════════════════════════════════
# S3「錠と門」 20s / RW1 — 両方必須の初回
# 錠(開22)はFF2発でしか間に合わない(待つとタイムアップ)。
# 奥の閉門(閉1.5)は必ず閉まっている→RW必須。RW1発なので配分の迷いなし
# ════════════════════════════════════════════════════════════════════


def s3_route(r):
    r.walk(1.6, "段差へ")
    r.hops(3.0, 2, "射撃台(段差二段)へ")


def s3_noarrow(r):
    s3_route(r)
    r.lock_wait("Lock3", 22.0)
    r.gate_pass("Gate3", 1.5)


def s3_ffonly(r):
    s3_route(r)
    r.ff("Lock3", 10.0, dist=2.0)
    r.ff("Lock3", 10.0, dist=2.0)
    r.lock_wait("Lock3", 22.0)
    r.walk(3.5, "針山区間")
    r.gate_pass("Gate3", 1.5)


def s3_rwonly(r):
    s3_route(r)
    r.lock_wait("Lock3", 22.0)
    r.walk(3.5)
    r.rw("Gate3", 10.0, dist=1.2, label="1発では届かない")
    r.gate_reopen_pass("Gate3", 1.5)


def s3_plan(r):
    s3_route(r)
    r.ff("Lock3", 10.0, dist=2.0, label="錠へ1本目")
    r.ff("Lock3", 10.0, dist=2.0, label="錠へ2本目")
    r.lock_wait("Lock3", 22.0)
    r.walk(1.2)
    r.hops(2.0, 2, "針山")
    r.walk(1.0, "Gate3前")
    r.rw("Gate3", 10.0, dist=1.2, label="閉門を呼び戻す")
    r.gate_reopen_pass("Gate3", 1.5)
    r.walk(2.6, "ゴール")


ALL_OK &= report("S3 錠と門", 20, 1, [
    ("矢なし", s3_noarrow, False),
    ("FFのみ", s3_ffonly, False),
    ("RWのみ", s3_rwonly, False),
    ("想定解", s3_plan, True),
], margin=(1.5, 6.0))

# ════════════════════════════════════════════════════════════════════
# S4「動かせない締切」 23s / RW2 — サンド+RW上限+退避ピット初出
# スラムA(閉1.8)でRW強制。錠(開25)×閉門B(閉13)のサンド:
# 待つと B は 26-10 = 16 >= 13 で呼び戻し不能 → 錠のFF早開けが唯一解
# 幅17.5: 針山2枚→スラムA x6.5→錠x8.6→刃ピットx11.6→閉門B x14.4→出口16.5
# ════════════════════════════════════════════════════════════════════
S4_SAW = dict(bx=12.6, amp=1.0, period=4.0, phase=0.0, pit0=12.0, pit1=13.2)


def s4_route_to_A(r):
    r.walk(1.5, "針山1へ")
    r.hops(2.6, 2, "針山1")
    r.walk(0.7)
    r.hops(2.4, 2, "針山2")
    r.walk(0.8, "スラムA前")


def s4_noarrow(r):
    s4_route_to_A(r)
    r.gate_pass("GateA4", 1.8)


def s4_rwonly(r):
    s4_route_to_A(r)
    r.rw("GateA4", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA4", 1.8)
    r.lock_wait("Lock4", 25.0)
    r.pit_cross("Saw4", **S4_SAW, x0=9.8, x1=14.7)
    r.rw("GateB4", 10.0, dist=1.2, label="残1発(上限10で届かない)")
    r.gate_reopen_pass("GateB4", 13.0)


def s4_plan(r):
    s4_route_to_A(r)
    r.rw("GateA4", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA4", 1.8)
    r.walk(1.2, "射撃位置")
    r.ff("Lock4", 10.0, dist=1.5, label="錠へ1本目")
    r.ff("Lock4", 10.0, dist=1.5, label="錠へ2本目")
    r.lock_wait("Lock4", 25.0)
    r.pit_cross("Saw4", **S4_SAW, x0=9.8, x1=14.7, label="退避ピットで刃越え")
    r.gate_pass("GateB4", 13.0, "サンドの締切")
    r.walk(2.1, "ゴール")


ALL_OK &= report("S4 動かせない締切", 23, 2, [
    ("矢なし", s4_noarrow, False),
    ("FFのみ", s4_noarrow, False),
    ("RWのみ", s4_rwonly, False),
    ("想定解", s4_plan, True),
], margin=(1.5, 6.0))

# ════════════════════════════════════════════════════════════════════
# S5「時の昇降機」 26s / RW3 — 2階建て+橋エレベーター+大玉レース
# デッキへの唯一の手段 = リフト(自然降下14)に乗ってRWで巻き上げ。
# 大玉が実11.6+αにゴールを破壊 → 自然降下待ちでは手遅れ=FF強制。
# スラム(閉2)はFF経路なら時計が若く1発、待ち経路は2発 → RW3では足りない
# 幅18.5: 針山→リフトx7(板5.5-8.5)→デッキ[9,18.5]y4→スラムx9.5→退避台x12.4/13.2
#          →大玉x11(速0.5)→終錠x16.2(開30)→出口x17.7
# ════════════════════════════════════════════════════════════════════
S5_BALL = dict(bx=11.0, rollT=0.0, speed=0.5)
S5_GOAL = 17.7


def s5_ground(r):
    r.walk(1.0, "針山へ")
    r.hops(1.6, 2, "針山")
    r.walk(1.1, "リフト射撃位置x4.5")


def s5_noarrow(r):
    s5_ground(r)
    r.wait(14.0, "リフト自然降下")
    r.dead = "デッキへ上がる手段がない(リフトはRWでしか上がらない)"


def s5_ffonly(r):
    s5_ground(r)
    r.ff("Lift5", 10.0, dist=3.0)
    r.ff("Lift5", 4.0, dist=3.0)
    r.dead = "リフトは降ろせても上がれない(デッキ到達不能)"


def s5_rwonly(r):
    s5_ground(r)
    r.wait(max(0.0, 14.0 - r.clock("Lift5")), "自然降下待ち")
    r.walk(2.5, "乗り込み")
    r.rw("Lift5", 10.0, dist=0.5, label="巻き上げ")
    r.wait(0.6)
    r.walk(1.0, "スラム前")
    r.rw("Gate5", 10.0, dist=1.0, label="1発目(時計が古く10では0にならない…実効10)")
    r.gate_reopen_pass("Gate5", 2.0)
    r.rw("Gate5", 10.0, dist=1.0, label="2発目でようやく開く")
    r.gate_reopen_pass("Gate5", 2.0)
    r.goal_alive("Ball5", **S5_BALL, goal_x=S5_GOAL, label="玉に矢が残っていない")


def s5_plan(r):
    s5_ground(r)
    r.ff("Lift5", 10.0, dist=3.0, label="リフトへ1本目")
    r.ff("Lift5", 4.0, dist=3.0, label="リフトへ2本目(時計14で着地)")
    r.walk(2.5, "乗り込み")
    r.rw("Lift5", 10.0, dist=0.5, label="乗ったまま巻き上げ=上昇!")
    r.wait(0.6, "デッキへ移る")
    r.walk(1.0, "スラム前")
    r.rw("Gate5", 10.0, dist=1.0, label="呼び戻し(時計が若く1発)")
    r.gate_reopen_pass("Gate5", 2.0)
    r.walk(2.9, "退避台へ")
    r.hops(0.8, 2, "退避台に上る")
    r.rw("Ball5", 10.0, dist=2.0, label="大玉を呼び戻す(下を逆走)")
    r.wait(0.8, "通過待ち")
    r.walk(3.0, "デッキを右へ")
    r.ball_block_check("Ball5", **S5_BALL, px=16.2, label="先行確認")
    r.ff("Lock5", 10.0, dist=1.5, label="終錠へ1本目")
    r.ff("Lock5", 10.0, dist=1.5, label="終錠へ2本目")
    r.lock_wait("Lock5", 30.0)
    r.goal_alive("Ball5", **S5_BALL, goal_x=S5_GOAL, label="レース勝利")
    r.walk(1.5, "ゴール")


ALL_OK &= report("S5 時の昇降機", 26, 3, [
    ("矢なし", s5_noarrow, False),
    ("FFのみ", s5_ffonly, False),
    ("RWのみ(スラムに2発必要で玉に届かない)", s5_rwonly, False),
    ("想定解", s5_plan, True),
], margin=(1.5, 10.0))

# ════════════════════════════════════════════════════════════════════
# S6「導火線」 30s / RW2 — 爆弾の遠隔起爆+三重の時限
# 壁W(x8.2)は爆弾B(自然爆発24)でしか壊れない。待つと閉門C(閉12)が
# 24.7-10=14.7>=12 で呼び戻せず、2発使うとスラムA分が無い → FF起爆が唯一解
# 幅17: 針山2→スラムA x5.2(閉1.7)→爆弾+壁x8.2→閉門C x11→針山→錠x13.5(開22)→出口16.2
# ════════════════════════════════════════════════════════════════════


def s6_route_to_A(r):
    r.walk(1.2, "針山1へ")
    r.hops(2.6, 2, "針山1")
    r.walk(0.6)
    r.hops(2.4, 2, "針山2")
    r.walk(0.6, "スラムA前")


def s6_noarrow(r):
    s6_route_to_A(r)
    r.gate_pass("GateA6", 1.7)


def s6_rwonly(r):
    s6_route_to_A(r)
    r.rw("GateA6", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA6", 1.7)
    r.walk(1.6, "爆弾の安全圏x6.3で待機")
    r.bomb_wait_boom("BombB", 24.0)
    r.walk(2.6, "瓦礫を抜けC前へ")
    r.rw("GateC6", 10.0, dist=1.2, label="1発目(14.7>=12で届かない)")
    r.gate_reopen_pass("GateC6", 12.0)


def s6_plan(r):
    s6_route_to_A(r)
    r.rw("GateA6", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA6", 1.7)
    r.walk(1.1, "安全圏x6.3から狙う")
    r.ff("BombB", 10.0, dist=1.9, label="導火線を1本目")
    r.ff("BombB", 10.0, dist=1.9, label="2本目→即起爆(安全圏の外から)")
    r.wait(0.5, "爆発")
    r.walk(2.6, "瓦礫を抜ける")
    r.gate_pass("GateC6", 12.0, "まだ開いている")
    r.hops(1.8, 2, "針山3")
    r.walk(0.9, "錠前")
    r.ff("Lock6", 10.0, dist=1.5, label="錠へ(半分だけ前借り)")
    r.lock_wait("Lock6", 22.0)
    r.walk(2.4, "ゴール")


ALL_OK &= report("S6 導火線", 30, 2, [
    ("矢なし", s6_noarrow, False),
    ("FFのみ", s6_noarrow, False),
    ("RWのみ", s6_rwonly, False),
    ("想定解", s6_plan, True),
], margin=(1.5, 8.0))

# ════════════════════════════════════════════════════════════════════
# S7「時計塔の往復」 36s / RW3 — 2階往復+矢でしか押せないボタン
# 出口は下段の袋小路(西=格子L、東=全高壁)。格子はボタン連動、ボタンは
# 塔の上(どこからも届かない)=デッキ左端からFF矢で撃つしかない → FF構造強制。
# デッキ左の錠(開26)は「待つ17秒 vs FF18払う9秒」の経済選択。
# 幅18: 針山→スラムA x5.2→(地上を東へ)→階段x15-17→デッキ[2.5,17]y4.4を西へ
#        →刃ピットx10.5→錠x4(開26)→ボタン射撃→降下→格子x8→出口x9
# ════════════════════════════════════════════════════════════════════
S7_SAW = dict(bx=10.5, amp=1.2, period=4.0, phase=0.0, pit0=11.1, pit1=9.9)  # 西向きに渡る


def s7_route_to_A(r):
    r.walk(1.2, "針山1へ")
    r.hops(2.4, 2, "針山1")
    r.walk(0.6)
    r.hops(2.2, 2, "針山2")
    r.walk(0.6, "スラムA前")


def s7_noarrow(r):
    s7_route_to_A(r)
    r.gate_pass("GateA7", 1.6)


def s7_rwonly(r):
    s7_route_to_A(r)
    r.rw("GateA7", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA7", 1.6)
    r.walk(9.8, "地上を東へ")
    r.hops(2.4, 4, "階段でデッキへ")
    r.walk(5.5, "デッキを西へ")
    r.pit_cross("Saw7", **S7_SAW, x0=13.0, x1=8.2, label="(西向き)")
    r.walk(4.0, "錠前")
    r.lock_wait("LockD7", 26.0)
    r.dead = "ボタンはFF矢でしか押せない → 格子が開かず出口に入れない"


def s7_plan(r):
    s7_route_to_A(r)
    r.rw("GateA7", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA7", 1.6)
    r.walk(9.8, "地上を東へ(頭上のデッキと塔を観察)")
    r.hops(2.4, 4, "階段でデッキへ")
    r.walk(5.5, "デッキを西へ")
    r.pit_cross("Saw7", **S7_SAW, x0=13.0, x1=8.2, label="(西向き)")
    r.walk(4.0, "錠D前")
    r.ff("LockD7", 10.0, dist=1.5, label="錠Dへ1本目")
    r.ff("LockD7", 8.0, dist=1.5, label="錠Dへ2本目(待つより9秒得)")
    r.lock_wait("LockD7", 26.0)
    r.walk(0.7, "デッキ左端")
    r.ff("ButtonB7", 2.0, dist=3.2, label="塔上のボタンへFF矢→格子が開く")
    r.walk(0.5, "縁へ")
    r.wait(0.5, "飛び降り")
    r.walk(5.2, "地上を東へ、開いた格子x8をくぐる")
    r.walk(1.0, "袋小路の出口へ")


ALL_OK &= report("S7 時計塔の往復", 36, 3, [
    ("矢なし", s7_noarrow, False),
    ("FFのみ", s7_noarrow, False),
    ("RWのみ", s7_rwonly, False),
    ("想定解", s7_plan, True),
], margin=(2.0, 10.0))

# ════════════════════════════════════════════════════════════════════
# S8「時計職人の卒業試験」 38s / RW4 — 全メカニクスのスケジューリング試験
# ①スラムA(RW) ②地上爆弾の遠隔起爆(FF)③サンド閉門C ④デッキのスラムD(RW)
# ⑤終錠(開36)は「種まきFF2発で実16に前倒し」— デッキの爆弾F(自然20)が
#    待機地点を吹き飛ばすため、1発種まき(開26)や自然待ち(36)では焼死する。
#    代替: 爆弾FをRWで遅らせて1発種まきで凌ぐ(資源トレード)も可
# ⑥銀行: 高所の空転ノコへRWで返金(任意)
# 幅20: 針山2→スラムA x7(閉1.6)→爆弾x9.6+壁x10.5(自然26)→閉門C x12.2(閉13)
#        →階段x13.2-14.6→デッキ[14.7,20]y4.4→スラムD x15.9(閉8.5)→爆弾F x17.6(自然20)
#        →終錠x19(開36)→出口x19.6
# ════════════════════════════════════════════════════════════════════


def s8_route_to_A(r):
    r.walk(1.0, "針山1へ")
    r.hops(2.2, 2, "針山1")
    r.walk(0.8)
    r.hops(2.0, 2, "針山2")
    r.walk(0.7, "スラムA前")


def s8_noarrow(r):
    s8_route_to_A(r)
    r.gate_pass("GateA8", 1.6)


def s8_rwonly(r):
    s8_route_to_A(r)
    r.rw("GateA8", 4.0, dist=1.5, label="スラムA")
    r.gate_reopen_pass("GateA8", 1.6)
    r.walk(1.0, "安全圏で待機")
    r.bomb_wait_boom("BombB8", 26.0)
    r.walk(2.0, "瓦礫を抜けC前")
    r.rw("GateC8", 10.0, dist=1.2, label="C 1発目")
    r.gate_reopen_pass("GateC8", 13.0)
    r.rw("GateC8", 10.0, dist=1.2, label="C 2発目")
    r.gate_reopen_pass("GateC8", 13.0)
    r.hops(2.4, 4, "階段→デッキ")
    r.walk(1.0, "スラムD前")
    r.rw("GateD8", 10.0, dist=1.2, label="D 残り1発(時計-10でもまだ閉)")
    r.gate_reopen_pass("GateD8", 8.5)


def s8_plan(r):
    s8_route_to_A(r)
    r.rw("GateA8", 4.0, dist=1.5, label="スラムA呼び戻し")
    r.gate_reopen_pass("GateA8", 1.6)
    r.walk(1.0, "安全圏x8.0から")
    r.ff("BombB8", 10.0, dist=1.6, label="導火線1本目")
    r.ff("BombB8", 10.0, dist=1.6, label="2本目(時計まだ25前後)")
    r.ff("BombB8", 4.0, dist=1.6, label="3本目→起爆")
    r.wait(0.5, "爆発")
    r.walk(2.0, "瓦礫を抜ける")
    r.gate_pass("GateC8", 13.0, "サンドの締切")
    r.walk(1.0, "階段へ")
    r.hops(2.4, 4, "階段→デッキ")
    r.walk(1.0, "スラムD前")
    r.rw("GateD8", 10.0, dist=1.2, label="D呼び戻し(時計が若く1発)")
    r.gate_reopen_pass("GateD8", 8.5)
    r.ff("LockE8", 10.0, dist=2.7, label="◆種まき1: 終錠へ")
    r.ff("LockE8", 10.0, dist=2.7, label="◆種まき2: 爆弾Fが吹く前に開くように")
    r.rw("BankSaw8", 10.0, dist=4.5, label="◆銀行: 空転ノコへ返金")
    r.lock_wait("LockE8", 36.0)
    if r.clock("BombF8") >= 20.0:
        r.dead = r.dead or f"爆弾F爆発時に待機圏内(実{r.real:.1f} >= 20)"
    r.note(f"爆弾Fまで残り{20.0 - r.clock('BombF8'):.1f}s で錠を通過")
    r.walk(1.2, "爆風圏を抜けてゴール")


def s8_single_seed(r):
    """種まき1発だけ → 錠は実26に開くが待機地点が実20に爆殺される"""
    s8_route_to_A(r)
    r.rw("GateA8", 4.0, dist=1.5)
    r.gate_reopen_pass("GateA8", 1.6)
    r.walk(1.0)
    r.ff("BombB8", 10.0, dist=1.6)
    r.ff("BombB8", 10.0, dist=1.6)
    r.ff("BombB8", 4.0, dist=1.6)
    r.wait(0.5)
    r.walk(2.0)
    r.gate_pass("GateC8", 13.0)
    r.walk(1.0)
    r.hops(2.4, 4)
    r.walk(1.0)
    r.rw("GateD8", 10.0, dist=1.2)
    r.gate_reopen_pass("GateD8", 8.5)
    r.ff("LockE8", 10.0, dist=2.7, label="種まき1発のみ")
    r.lock_wait("LockE8", 36.0)
    if r.clock("BombF8") >= 20.0:
        r.dead = r.dead or f"爆弾Fが待機中に爆発(実{r.real:.1f} >= 20)"
    r.walk(1.2)


ALL_OK &= report("S8 時計職人の卒業試験", 38, 4, [
    ("矢なし", s8_noarrow, False),
    ("FFのみ", s8_noarrow, False),
    ("RWのみ", s8_rwonly, False),
    ("種まき1発(爆弾Fに焼かれる)", s8_single_seed, False),
    ("想定解", s8_plan, True),
], margin=(2.0, 10.0))

print("\n" + "═" * 68)
print("判定:", "ALL OK" if ALL_OK else "NG あり — 数値を調整せよ")
