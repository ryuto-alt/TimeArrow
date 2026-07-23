# -*- coding: utf-8 -*-
"""ステージを作り直して、4種の検算を全部通す単一の入口。

    python tools/check.py          生成 + 全検算
    python tools/check.py --quiet  結果行だけ

なぜ1本にまとめるか: ジオメトリを1u動かすだけで別のステージの別の性質が壊れる。
実際にこのループ中だけで、S6の支柱を入れ忘れて上層を飛ばせる/S8のピットが床板に
埋まって刃が回避不能/S7の谷を動かしたら塔のボタンが地上から撃てる、が起きた。
どれも「気づけば直せる」類で、気づけるかどうかに賭けないための機械検査。

  gen_stages   ジオメトリ生成 + 参照名/スラム門の整合
  sim_stages   時間の収支(矢なし/FFのみ/RWのみ不成立 + マージン帯 + 純移動8秒未満)
  audit_paths  経路の強制(徒歩で出口不可 / 上層スキップ不可 / 退避ピットが生きている)
  audit_shots  射線パズル(禁止射点から当たらない / 意図した射点からは当たる)
"""
import subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
QUIET = "--quiet" in sys.argv

STEPS = [
    ("gen_stages.py", "ジオメトリ生成"),
    ("sim_stages.py", "時間の収支"),
    ("audit_paths.py", "経路の強制"),
    ("audit_shots.py", "射線パズル"),
]

env = dict(os.environ, PYTHONIOENCODING="utf-8")
results, failed = [], False
for script, label in STEPS:
    r = subprocess.run([sys.executable, os.path.join(HERE, script)],
                       capture_output=True, text=True, encoding="utf-8", env=env, cwd=HERE)
    ok = r.returncode == 0
    results.append((label, script, ok))
    if not ok:
        failed = True
    if not QUIET or not ok:
        print(f"\n{'─' * 68}\n▶ {label} ({script})\n{'─' * 68}")
        print((r.stdout or "").rstrip())
        if r.stderr.strip():
            print(r.stderr.rstrip())
    if not ok:
        break                      # 生成が壊れていたら後段を回しても意味がない

print(f"\n{'═' * 68}")
for label, script, ok in results:
    print(f" {'✓' if ok else '✗'} {label:<12} ({script})")
skipped = [s for s, _ in STEPS if s not in {r[1] for r in results}]
for s in skipped:
    print(f" - {'(未実行)':<12} ({s})")
print("═" * 68)
print("判定:", "ALL OK — 出荷できる状態" if not failed else "NG — 上のログを見て直すこと")
sys.exit(1 if failed else 0)
