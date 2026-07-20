"""全ステージのテストプレイ。矢なし総当たり探索と、意図した解法の再生を回す。"""

import sys

from timearrow_sim import Inputs, jump_metrics, load
from solve import explore, one_shot_search, replay, shot_scan

STAGES = ["stage1", "stage2", "stage3", "stage4", "stage5"]


def aim(deg):
    import math
    return (math.cos(math.radians(deg)), math.sin(math.radians(deg)))


# 意図した解法(時刻, 入力)。draw=True の区間が引き絞り、False に戻った瞬間に発射。
SOLUTIONS = {
    "stage1": [
        (0.0, Inputs(move=1)),
        (1.05, Inputs(move=0, draw=True, aim=aim(37))),   # 的を狙う
        (1.15, Inputs(move=0, draw=False, aim=aim(37))),  # 発射
        (2.2, Inputs(move=1)),                            # 橋を渡ってゴールへ
    ],
    "stage2": [
        (0.00, Inputs(move=1)),
        (0.40, Inputs(move=0, draw=True, aim=aim(90))),   # 真上のボタンへ
        (0.50, Inputs(move=0, draw=False, aim=aim(90))),
        (1.25, Inputs(vert=1)),                           # 蔦を登る(途中で矢を回収)
        (2.60, Inputs(move=1)),                           # 登りきって右へ→Ledge2 に落ちる
        (3.00, Inputs(move=0, draw=True, aim=aim(0))),    # 板の上から水平撃ち
        (3.10, Inputs(move=0, draw=False, aim=aim(0))),
        (4.10, Inputs(move=1)),
        (4.90, Inputs(move=1, jump=True)),                # 橋へ跳び乗る
        (5.40, Inputs(move=1)),
    ],
    "stage3": [
        (0.00, Inputs(move=1)),
        (0.30, Inputs(move=1, jump=True)),                # 段に跳び乗る
        (0.90, Inputs(move=0, draw=True, aim=aim(37))),   # 1つ目のボタン
        (1.00, Inputs(move=0, draw=False, aim=aim(37))),
        (1.90, Inputs(move=1)),                           # リフト1へ渡る
        (2.30, Inputs(move=0)),
        (2.40, Inputs(move=0, jump=True)),                # 真上に跳んで矢を回収
        (3.10, Inputs(move=0, draw=True, aim=aim(24))),   # 2つ目のボタン
        (3.20, Inputs(move=0, draw=False, aim=aim(24))),
        (4.10, Inputs(move=1)),
        (4.20, Inputs(move=1, jump=True)),                # リフト1→リフト2へ跳ぶ
        (5.00, Inputs(move=1)),
    ],
    "stage4": [
        (0.0, Inputs(move=1)),
        (1.55, Inputs(move=0, draw=True, aim=aim(0))),    # 迫る壁を至近で撃つ
        (1.60, Inputs(move=0, draw=False, aim=aim(0))),
        (1.65, Inputs(move=1)),                           # ゴースト中にすり抜ける
        (2.30, Inputs(move=0, draw=True, aim=aim(0))),    # ドアを引き絞って射抜く
        (4.20, Inputs(move=0, draw=False, aim=aim(0))),
        (4.60, Inputs(move=1)),
    ],
    "stage5": [
        (0.00, Inputs(move=1)),                           # 天井を右へ→動く床に乗る
        (0.80, Inputs(move=0)),                           # 床が下がるのを待つ
        (2.30, Inputs(move=1)),                           # 下がりきった隙に仕切りをくぐる
        (3.00, Inputs(move=0, draw=True, aim=aim(0))),    # ドアを引き絞って射抜く
        (4.90, Inputs(move=0, draw=False, aim=aim(0))),
        (5.40, Inputs(move=1)),
    ],
}


def main():
    only = sys.argv[1:] or STAGES
    w = load("stage1")
    print("■ プレイヤー性能")
    for k, v in jump_metrics(w).items():
        print(f"   {k}: {v}")
    print()
    for s in only:
        print(f"■ {s}")
        goal, reach, maxx = explore(s)
        print(f"   矢なし総当たり: {'クリアできてしまう ← 要修正' if goal else 'クリア不可 OK'}"
              f" (到達可能な最大X {maxx:.1f} / 到達点 {len(reach)})")
        # 場外へ落下中(=どのみち死ぬ)の地点からの射撃は数えない
        reach = {p for p in reach if -0.5 <= p[0] <= 16.5 and -0.5 <= p[1] <= 10.0}
        hits = shot_scan(s, reach, deg_step=2.0)
        for name, shots in sorted(hits.items()):
            pts = sorted({(p[0], p[1]) for p in shots})
            print(f"   撃てるターゲット {name}: {len(shots)}通り  発射地点例 {pts[:4]}")
        bad = one_shot_search(s)
        print(f"   1射ショートカット: {('抜けられる ' + str(bad)) if bad else 'なし'}")
        sol = SOLUTIONS.get(s)
        if sol:
            r = replay(s, sol)
            print(f"   意図した解法: {r['result']} t={r['t']}"
                  + (f" why={r.get('why')}" if r.get("why") else "")
                  + (f" 最終位置 x={r.get('x')} y={r.get('y')}" if "x" in r else ""))
        print()


if __name__ == "__main__":
    main()
