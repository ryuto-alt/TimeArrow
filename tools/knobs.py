# -*- coding: utf-8 -*-
"""TimeArrow ステージのタイミング定数(単一の真実源)。

gen_stages.py(シーン生成)と sim_stages.py(成立性検証)の両方がここを import する。
ジオメトリ(座標)は gen_stages.py 側で固定。ここにあるのは時間の knob だけ。
チューニング担当はこのファイルと sim_stages.py のプランだけを編集すること。

各ステージの成立条件(sim が機械検証):
  1. 矢なし/FFのみ/RWのみ の最適プランが全て失敗する
  2. 想定解が指定マージン帯でクリアできる
"""

K = {
    # S1「遅すぎる橋」2連橋のFFチュートリアル
    "s1": dict(limit=33.5, rw=1, rise1=12.0, rise2=32.0),

    # S2「四枚の閉門回廊」スラム(RW)とスプリント(急げば間に合う)の混合
    "s2": dict(limit=18.0, rw=3, closeA=2.8, closeB=8.0, closeC=12.5, closeD=15.5),

    # S3「三つの錠の取引」種まきFF+二重スラム+サンド
    "s3": dict(limit=38.0, rw=2, lock1=18.0, slam1=3.5, slam2=8.5, lock2=30.0, closeZ=26.0),

    # S4「動かせない締切」サンド+刃ピット+動く壁(FFゴースト)
    "s4": dict(limit=43.0, rw=2, slamA=2.55, lockOpen=25.0, closeB=17.5,
               cwStart=5.0, cwSpeed=1.0, cwTravel=15.0, closeZ=32.0),

    # S5「時の昇降機・改」リフト+大玉チェイス+ツタ+フェリー+最上層
    "s5": dict(limit=66.0, rw=3, lift=14.0, slamG=2.6, ballRoll=4.0, ballSpeed=0.6,
               lockD=30.0, vineGrow=33.0, ferryP=6.0, closeY=44.0, lockZ=52.0),

    # S6「二本の導火線」地上とレッジの爆弾×2
    "s6": dict(limit=74.0, rw=3, slamA=2.65, boom1=24.0, closeC=12.0,
               boom2=40.0, closeE=20.0, lockZ=55.0),

    # S7「時計塔大回廊」ボタン+2リズムの刃+ツタ+最上層
    "s7": dict(limit=100.0, rw=4, slamA=2.1, lockD=30.0, sawP1=4.0, sawP2=3.0,
               vineGrow=40.0, sawP3=5.0, lockZ=68.0),

    # S8「時計職人の卒業試験・大」4フェーズ総合
    "s8": dict(limit=96.0, rw=5, slamA=2.4, boomB=26.0, closeC=13.0, slamD=10.5,
               lockE=36.0, boomF=22.0, closeG=30.0, lift=55.0,
               ballRoll=60.0, ballSpeed=0.5, closeY=45.0, lockZ=80.0),
}
