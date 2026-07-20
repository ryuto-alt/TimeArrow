"""意図した解法を1コマ送りで追う。解法タイムラインを詰めるための道具。"""

import sys

from timearrow_sim import DT, Inputs, load
from testplay import SOLUTIONS

stage = sys.argv[1]
every = int(sys.argv[2]) if len(sys.argv) > 2 else 6
watch = sys.argv[3:]

w = load(stage)
events = sorted(SOLUTIONS[stage], key=lambda e: e[0])
cur, ei = Inputs(), 0
for i in range(int(w.T / DT)):
    t = i * DT
    jump_now = False
    while ei < len(events) and events[ei][0] <= t + 1e-9:
        n = events[ei][1]
        jump_now = n.jump
        cur = Inputs(n.move, False, n.vert, n.draw, n.aim)
        ei += 1
    cleared, death = w.step(Inputs(cur.move, jump_now, cur.vert, cur.draw, cur.aim))
    if i % every == 0 or death or cleared:
        p = w.player
        extra = "  ".join(f"{n}=({w.pos[n][0]:.2f},{w.pos[n][1]:.2f})" for n in watch)
        arrow = "飛" if p.arrow_flying else ("刺:" + str(p.arrow_target) if p.arrow_stuck else "手")
        print(f"t={t:5.2f} x={p.x:6.2f} y={p.y:5.2f} ground={int(p.grounded)} "
              f"ride={p.ride or '-':10s} 矢={arrow:12s} {extra}")
    if death:
        print("→ 死亡:", death)
        break
    if cleared:
        print("→ クリア", round(t, 2))
        break
else:
    print("→ タイムアップ")
