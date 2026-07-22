# -*- coding: utf-8 -*-
"""TimeArrow ステージ成立性シミュレータ。

プレイヤー物理(gen_stages.py と同じ値):
  移動 5/s / ジャンプ初速11.6・重力40 → 高さ1.68・滞空0.58s・水平2.9
  針山ホップ = 距離/5 + 着地調整0.15s×ジャンプ数
  弓: 引きmin0.15s(+2)〜max3s(+10)。構え中は世界0.25倍速(タイマーも)。
      発射→命中0.1s→刺さり0.4s→帰還≈0.5s = 連射サイクル実時間≈1.0s+引き時間
  時間経済: 先送り=タイマー+量*0.5 / 後戻り=タイマー-実際に戻せた量*0.5(対象時計は0で底打ち)
  ギミックの時計は実時間で進む。閉門はドロー中もほぼ実時間(スロー中は0.25倍)。

各ステージを「矢なし最適プラン」と「想定プラン」の2通りで評価し、
  ・矢なしでクリア可能なら NG (弓矢必須仕様を満たさない)
  ・想定プランのタイマーマージンが 1.0〜4.0s の範囲なら OK
を判定する。プランは工程のリスト(下のop群)で記述する。
"""

WALK = 5.0
DRAW_FULL = 3.0     # 実時間
DRAW_SLOW = 0.25    # 構え中のタイマー倍率
SHOT_OVERHEAD = 1.0 # 発射→命中→刺さり→帰還(実時間)

class Run:
    def __init__(self, limit, shots):
        self.real = 0.0      # 実経過
        self.timer = 0.0     # 制限時間ゲージ
        self.limit = limit
        self.shots = shots   # 後戻り残数
        self.log = []
        self.dead = None

    def note(self, msg):
        self.log.append(f"  t={self.timer:5.1f}/real={self.real:5.1f}  {msg}")

    def advance(self, dt_real, scale=1.0):
        self.real += dt_real
        self.timer += dt_real * scale

    def walk(self, dist, label=""):
        self.advance(dist / WALK)
        self.note(f"walk {dist:.1f}u {label}")

    def hops(self, dist, jumps, label=""):
        self.advance(dist / WALK + jumps * 0.15)
        self.note(f"hops {dist:.1f}u x{jumps} {label}")

    def wait_until_real(self, t, label=""):
        if t > self.real:
            self.advance(t - self.real)
            self.note(f"wait→real {t:.1f} {label}")

    def draw(self, amount):
        """引き絞り(実時間)。タイマーはスロー分だけ進む。実時間を返す"""
        frac = max(0.0, min(1.0, (amount - 2.0) / 8.0))
        d = 0.15 + frac * (DRAW_FULL - 0.15)
        self.advance(d + SHOT_OVERHEAD, scale=DRAW_SLOW)
        return d

    def ff(self, amount, label=""):
        self.draw(amount)
        self.timer += amount * 0.5
        self.note(f"FF+{amount:.1f} (代償{amount*0.5:.1f}) {label}")

    def rw(self, amount, target_clock, label=""):
        """後戻り矢。対象の時計(実時間ベース)で底打ちした実効量だけ返金"""
        if self.shots <= 0:
            self.dead = f"REWIND切れ: {label}"
            return 0.0
        self.shots -= 1
        self.draw(amount)
        actual = min(amount, target_clock)
        self.timer = max(0.0, self.timer - actual * 0.5)
        self.note(f"RW-{amount:.1f}(実効{actual:.1f}, 返金{actual*0.5:.1f}) {label}")
        return actual

    def check_close(self, close_t, label=""):
        """閉門: 実時間 close_t までに通過が必要"""
        if self.real >= close_t:
            self.dead = f"閉門済み({label}: 実{self.real:.1f} >= {close_t})"

    def lock(self, open_t, label=""):
        """時限錠: 対象時計(≒実時間+FF済み)が open_t になるまで待つ"""
        self.wait_until_real(open_t, f"開錠待ち {label}")

    def finish(self):
        if self.dead:
            return f"✗ 失敗: {self.dead}"
        if self.timer >= self.limit:
            return f"✗ タイムアップ (t={self.timer:.1f} >= {self.limit})"
        return f"✓ クリア t={self.timer:.1f}/{self.limit} (マージン{self.limit-self.timer:.1f})"


def report(name, limit, shots, noarrow, plan):
    print(f"\n━━ {name} (制限{limit}s / まき戻し{shots}) ━━")
    r1 = Run(limit, 0)
    noarrow(r1)
    v1 = r1.finish()
    req = "✓ 弓矢必須" if v1.startswith("✗") else "✗✗ 弓矢なしでクリア可能!!"
    print(f" 矢なし最適: {v1}  → {req}")
    r2 = Run(limit, shots)
    plan(r2)
    v2 = r2.finish()
    print(f" 想定プラン: {v2}")
    for l in r2.log:
        print(l)
    return v1.startswith("✗") and v2.startswith("✓")


ok = True

# ── S1「時は金なり」制限12 落下橋riseTime=14(>制限) → FF必須 ──────────────
def s1_no(r):
    r.walk(5.5, "左床右端へ")
    r.wait_until_real(14.0, "橋の自然落下(14s)")   # 制限12を必ず超える
    r.walk(9.0, "橋+右床→ゴール")
def s1_plan(r):
    r.walk(4.0, "射撃位置へ")
    r.ff(10.0, "橋(的)へフル")
    r.ff(2.0, "橋へ追いタップ")           # 橋時計 real+12 >= 14
    r.walk(10.5, "橋を渡ってゴール")
ok &= report("S1 時は金なり", 12, 1, s1_no, s1_plan)

# ── S2「二枚の閉門」制限10 GateA閉1.5(最速1.8到達) GateB閉3.0 → RW必須 ────
def s2_no(r):
    r.walk(2.2, "針山手前")
    r.hops(3.6, 3, "針山")
    r.walk(1.2, "GateAへ")               # 最速でも real≈2.9 > 2.2
    r.check_close(1.5, "GateA")
    r.walk(4.0, "GateB")
    r.walk(3.0, "ゴール")
def s2_plan(r):
    r.walk(2.2, "針山手前")
    r.hops(3.6, 3, "針山")
    r.walk(1.2, "GateA前")
    r.rw(2.8, r.real, "GateA呼び戻し")    # A時計→0.9 (窓[0,2.2)に復帰)
    r.walk(4.0, "GateB前")
    r.rw(3.2, r.real, "GateB呼び戻し")
    r.walk(3.5, "ゴール")
ok &= report("S2 二枚の閉門", 9, 3, s2_no, s2_plan)

# ── S3「錠前と締切のサンド」制限15 錠x6=10s→閉門x10.5=9s(実時間) → FF必須 ──
def s3_no(r):
    r.hops(2.5, 2, "針山")
    r.walk(2.0, "錠前(開10)")
    r.lock(10.0, "LockGate3")
    r.walk(2.5, "刃を抜けて")
    r.check_close(9.0, "ClosingGate3")     # 10.5到達=実10.5 > 9 で必ず死ぬ
    r.walk(4.9, "ゴール")
def s3_plan(r):
    r.hops(2.5, 2, "針山")
    r.walk(2.0, "錠前前(実1.4)")
    r.ff(8.6, "錠前へ(時計→10)")
    r.walk(1.5, "刃(周期4)手前")
    r.advance(1.0); r.note("刃の間合い待ち")
    r.walk(1.0, "閉門(閉9)を実5.5頃に通過")
    r.check_close(9.0, "ClosingGate3")
    r.hops(1.5, 1, "段差")
    r.walk(4.4, "ゴール")
    if r.shots > 0:
        r.rw(8.0, 8.0, "刃に銀行(-8=2周期,位相不変)")
ok &= report("S3 錠前と締切のサンド", 13, 2, s3_no, s3_plan)

# ── S4「大玉と錠前」制限11 玉が実10にゴール破壊/錠開11 → 玉RW必須 ──────────
def s4_no(r):
    r.advance(0.4); r.note("高台から降りる")
    r.hops(3.6, 3, "針山A")
    r.hops(2.6, 2, "針山B")
    r.walk(4.0, "錠前(開11)")
    r.lock(11.0, "LockGate4")
    r.walk(1.7, "ゴール")
    if r.real >= 10.0:                     # 玉(速1.3,13u)が実10で破壊済み
        r.dead = "大玉がゴール破壊(実10)"
def s4_plan(r):
    r.advance(0.4); r.note("高台から降りる")
    r.hops(3.6, 3, "針山A")
    r.hops(2.6, 2, "針山B")
    r.walk(4.0, "錠前前(実7.5)")
    r.rw(6.0, r.real, "大玉を-6(破壊を実16へ)")
    r.lock(11.0, "LockGate4")
    r.walk(1.7, "ゴール")
ok &= report("S4 大玉と錠前", 11, 2, s4_no, s4_plan)

# ── S5「時計職人」制限14 2階の閉門3.0(最速3.6) → RW必須 ─────────────────
def s5_no(r):
    r.advance(2.5); r.note("刃(周期4)を抜ける")
    r.hops(2.4, 2, "階段")
    r.walk(1.5, "2階の閉門")               # 実≈5.2 > 4.5
    r.check_close(3.0, "GateU")
    r.walk(2.0, "刃(周期3)")
    r.walk(3.0, "降りて錠前(開12)")
    r.lock(12.0, "LockGate5")
    r.walk(1.5, "ゴール")
def s5_plan(r):
    r.advance(2.5); r.note("刃(周期4)を抜ける")
    r.hops(2.4, 2, "階段")
    r.walk(1.5, "2階の閉門前")
    r.rw(2.5, r.real, "閉門を呼び戻す")
    r.advance(1.0); r.note("刃(周期3)の間合い")
    r.walk(2.0, "デッキ")
    r.walk(3.0, "降りて錠前")
    r.lock(12.0, "LockGate5")
    r.walk(1.5, "ゴール")
ok &= report("S5 時計職人", 14, 2, s5_no, s5_plan)

# ── S6「三重の締切・広域」制限14 幅24 閉門2.2(最速2.6)×玉13.3×錠16 → RW必須 ──
def s6_no(r):
    r.advance(0.4); r.note("高台から降りる")
    r.walk(1.1, "針山手前")
    r.hops(3.6, 3, "針山A")
    r.walk(3.0, "閉門(閉2.2)")             # 最速≈2.6 > 2.2
    r.check_close(2.2, "ClosingGate6")
    r.hops(2.6, 2, "針山B")
    r.walk(5.4, "錠前(開16)")
    r.lock(16.0, "LockGate6")
    r.walk(3.2, "ゴール")
    if r.real >= 13.3:                     # 玉(x11,速1.2)が実13.3にゴール破壊
        r.dead = "大玉がゴール破壊(実13.3)"
def s6_plan(r):
    r.advance(0.4); r.note("高台から降りる")
    r.walk(1.1, "針山手前")
    r.hops(3.6, 3, "針山A")
    r.walk(3.0, "閉門前(実2.6)")
    r.rw(2.2, r.real, "閉門を呼び戻す")
    r.hops(2.6, 2, "針山B")
    r.walk(5.4, "錠前前")
    r.rw(9.0, min(9.0, r.real), "大玉を-9(破壊を実22へ)")
    r.lock(16.0, "LockGate6")
    r.walk(3.2, "ゴール")
ok &= report("S6 三重の締切・広域", 14, 3, s6_no, s6_plan)

# ── S7「二階の銀行・広域」制限16 幅24 帰路の閉門14 < 帰着≈20 → RW+銀行必須 ──
def s7_no(r):
    r.walk(19.8, "地上を右へ(閉門x12は実2.4に通過)")
    r.hops(3.6, 3, "3段階段")
    r.walk(3.0, "デッキ左端方向へ")
    r.advance(4.0); r.note("丸ノコ3枚の間合い")
    r.walk(10.5, "デッキを左へ")
    r.lock(18.0, "上の錠前(開18)")
    r.walk(1.5, "左端から飛び降り")
    r.walk(8.0, "帰路: 閉門x12(閉14)")      # 実≈20 > 14 で必ず死ぬ
    r.check_close(14.0, "ReturnGate7")
    r.walk(7.4, "ゴールx19.4")
def s7_plan(r):
    r.walk(19.8, "地上を右へ")
    r.hops(3.6, 3, "3段階段")
    r.walk(3.0, "デッキへ")
    r.advance(4.0); r.note("丸ノコ3枚の間合い")
    r.walk(10.5, "デッキを左へ")
    r.rw(8.0, 8.0, "錠前待ち中に丸ノコへ銀行-8")
    r.lock(18.0, "上の錠前")
    r.walk(1.5, "飛び降り")
    r.walk(8.0, "帰路の閉門前(実≈20)")
    r.rw(7.5, 7.5, "帰路の閉門を呼び戻す(窓[0,14))")
    r.walk(7.4, "ゴール")
ok &= report("S7 二階の銀行・広域", 16, 3, s7_no, s7_plan)

# ── S8「卒業試験・広域」制限17 幅24 閉門2.0(RW)+錠開20(FF+14.5)+閉門14.5+銀行 ──
def s8_no(r):
    r.advance(2.5); r.note("丸ノコ(周期4)")
    r.hops(2.4, 2, "階段")
    r.walk(2.1, "デッキの閉門(閉2.0)")      # 最速≈4.2 > 2.0
    r.check_close(2.0, "GateU8")
    r.walk(2.5, "短周期ノコ")
    r.walk(3.0, "降りて錠前(開20)")
    r.lock(20.0, "LockGate8")
    r.hops(2.6, 2, "針山")
    r.walk(2.1, "最後の閉門(閉14.5)")       # 実≈21 > 14.5 で必ず死ぬ
    r.check_close(14.5, "ClosingGate8b")
    r.walk(2.2, "ゴール")
def s8_plan(r):
    r.advance(2.5); r.note("丸ノコ(周期4)")
    r.hops(2.4, 2, "階段")
    r.walk(2.1, "デッキの閉門前(実4.2)")
    r.rw(2.5, r.real, "閉門を呼び戻す")
    r.advance(1.0); r.note("短周期ノコの間合い")
    r.walk(2.5, "デッキ")
    r.walk(3.0, "降りて錠前前(実≈8)")
    r.ff(10.0, "錠前へフル")
    r.ff(4.5, "錠前へ追い矢(時計→20+)")
    r.hops(2.6, 2, "針山")
    r.walk(2.1, "最後の閉門(実≈13.7)")
    r.check_close(14.5, "ClosingGate8b")
    r.walk(2.2, "ゴール")
    r.rw(9.0, 9.0, "短周期ノコに銀行(-9=3周期,位相不変)")
ok &= report("S8 卒業試験・広域", 17, 3, s8_no, s8_plan)

print("\n" + ("═" * 60))
print("総合判定:", "ALL OK — 全ステージ弓矢必須+マージン正常" if ok else "NG あり — 数値を調整せよ")
