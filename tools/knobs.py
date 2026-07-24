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
    "s1": dict(limit=16.0, rw=1, rise1=12.0, rise2=9.0),

    # S2「四枚の閉門回廊」スラム(RW)とスプリント(急げば間に合う)の混合
    # rw=7 / limit=27: 2026-07-24ユーザー指示(35→30→27に締め直し)
    "s2": dict(limit=27.0, rw=7, closeA=2.8, closeB=8.6, closeC=12.5, closeD=15.5),

    # S3「風の谷」橋(FF)+ファンサージ(FF)+崩れ足場+閉門1枚(RW)
    "s3": dict(limit=33.0, rw=3, rise3=24.0, closeZ=14.0),

    # S4「昇降の工房」スラム(RW)+刃ピット+ハンマー+フェリー+昇降足場+錠(種まき)
    "s4": dict(limit=44.0, rw=4, slamA=2.55, ferryP=7.0,
               elevP=6.0, elevPh=0.0, lockZ=40.0),

    # S5「時の昇降機・改」リフト+大玉チェイス+ツタ+フェリー+最上層
    "s5": dict(limit=66.0, rw=3, lift=14.0, slamG=2.6, ballRoll=4.0, ballSpeed=0.6,
               lockD=30.0, vineGrow=33.0, ferryP=6.0, lockZ=52.0),

    # S6「導火線と気流」逆橋(RW)+爆弾2+ファンサージ+錆びた動く壁+終錠
    "s6": dict(limit=46.0, rw=2, rev6=3.0, boom1=5.0, boom2=5.0,
               cwStart=6.0, lockZ=34.0),

    # S7「時計塔大回廊」ボタン+2リズムの刃+ツタ+最上層
    "s7": dict(limit=100.0, rw=4, rev7=2.6, lockD=30.0, sawP1=4.0, sawP2=3.0,
               vineGrow=40.0, sawP3=5.0, lockZ=68.0),

    # S8「時計職人の卒業試験」門は2枚だけ。習った道具の総ざらい5フェーズ
    "s8": dict(limit=72.0, rw=4, slamA=2.4, boomB=5.0, boomF=5.0, lockE=34.0,
               rev8=3.0, ferryP=7.0, lift=58.0),
}
