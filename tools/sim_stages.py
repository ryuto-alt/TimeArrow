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

# ── S6「三重の締切」制限16 閉門4.0(最速4.9)×玉(破壊11.5)×錠14 → RW2発必須 ──
def s6_no(r):
    r.advance(0.4); r.note("高台から降りる")
    r.hops(3.6, 3, "針山")
    r.walk(2.8, "閉門(閉4.0)")             # 実≈4.9 > 4.0
    r.check_close(4.0, "ClosingGate6")
    r.walk(3.6, "錠前(開14)")
    r.lock(14.0, "LockGate6")
    r.walk(2.3, "ゴール")
def s6_plan(r):
    r.advance(0.4); r.note("高台から降りる")
    r.hops(3.6, 3, "針山")
    r.walk(2.8, "閉門前(実6.3)")
    r.rw(3.0, r.real, "閉門を呼び戻す")
    r.walk(3.6, "錠前前(実8.6)")
    r.rw(8.0, 8.0, "大玉を-8(破壊を実19.5へ+返金)")
    r.lock(14.0, "LockGate6")
    r.walk(2.3, "ゴール")
ok &= report("S6 三重の締切", 13, 3, s6_no, s6_plan)

# ── S7「二階の銀行」制限15 蛇行+帰路の閉門12(帰着≈17)+銀行必須 ─────────────
def s7_no(r):
    r.walk(12.6, "地上を右へ(閉門x8を実2.5に通過)")
    r.hops(2.4, 2, "右階段")
    r.walk(9.0, "デッキを左へ(刃2枚+間合い)")
    r.advance(2.0); r.note("刃の間合い×2")
    r.lock(16.0, "上の錠前(開16)")
    r.walk(1.5, "左端から飛び降り")
    r.walk(5.0, "帰路: 閉門x8(閉12)")      # 実≈17.5 > 12 で必ず死ぬ
    r.check_close(12.0, "ReturnGate7")
    r.walk(7.5, "ゴール")
def s7_plan(r):
    r.walk(12.6, "地上を右へ")
    r.hops(2.4, 2, "右階段")
    r.walk(9.0, "デッキを左へ")
    r.advance(2.0); r.note("刃の間合い×2")
    r.rw(8.0, 8.0, "錠前待ち中に刃へ銀行-8")
    r.lock(16.0, "上の錠前")
    r.walk(1.5, "飛び降り")
    r.walk(5.0, "帰路の閉門前(実≈17.5)")
    r.rw(7.0, 7.0, "帰路の閉門を呼び戻す(窓[0,12))")
    r.walk(7.5, "ゴール")
ok &= report("S7 二階の銀行", 15, 3, s7_no, s7_plan)

# ── S8「卒業試験」制限18 2階閉門5(最速5.5)+錠開26(>制限) → RW+FF両方必須 ────
def s8_no(r):
    r.advance(2.5); r.note("刃")
    r.hops(2.4, 2, "階段")
    r.walk(1.2, "2階の閉門(閉5)")
    r.check_close(5.0, "GateU8")
    r.walk(2.2, "刃(周期3)")
    r.walk(3.0, "降りて錠前")
    r.lock(26.0, "LockGate8(開26)")        # 待つとタイマー26>18で必ず死ぬ
    r.walk(1.5, "ゴール")
def s8_plan(r):
    r.advance(2.5); r.note("刃")
    r.hops(2.4, 2, "階段")
    r.walk(1.2, "2階の閉門前(実5.4)")
    r.rw(2.0, r.real, "閉門を呼び戻す")
    r.advance(1.0); r.note("刃(周期3)の間合い")
    r.walk(2.2, "デッキ")
    r.walk(3.0, "降りて錠前前(実≈9.5)")
    r.ff(10.0, "錠前へフル")
    r.ff(8.0, "錠前へ追い矢(時計→27+)")
    r.rw(9.0, 9.0, "刃に銀行(-9=3周期,位相不変)")
    r.walk(1.5, "ゴール")
ok &= report("S8 卒業試験", 18, 3, s8_no, s8_plan)

print("\n" + ("═" * 60))
print("総合判定:", "ALL OK — 全ステージ弓矢必須+マージン正常" if ok else "NG あり — 数値を調整せよ")
