# inject_draw_gauge.py -- 弓引き絞りゲージ(時計盤HUD)を全ステージへ注入する。
# 再実行しても重複しない(DrawGauge* を strip してから append)。
# 構成: DrawGauge(盤) > DrawGaugeArcFF(シアン扇/時計回り) + DrawGaugeArcRW(紫扇/反時計) + DrawGaugeHand(針)
# 制御は Player.lua(表示/fill/針回転/色)。位置は画面中央のプレイヤー右横。
import json
import os

SCENES = ['stage0.json', 'stage1.json', 'stage2.json', 'stage3.json', 'stage4.json']
BASE = os.path.join(os.path.dirname(__file__), '..', 'assets', 'scenes')

TR = {"position": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}


def ui_image(name, tex, rect, order, color, fill_dir=0, fill=1.0):
    return {
        "name": name,
        "transform": dict(TR),
        "uiRect": {"anchorMax": rect["aMax"], "anchorMin": rect["aMin"], "clipChildren": False,
                   "offsetMax": rect["oMax"], "offsetMin": rect["oMin"], "order": order,
                   "pivot": rect.get("pivot", [0.5, 0.5]), "rotation": 0.0, "skewX": 0.0,
                   "visible": True},
        "uiImage": {"texturePath": tex, "color": color, "uvMin": [0.0, 0.0], "uvMax": [1.0, 1.0],
                    "sliceBorder": [0.0, 0.0, 0.0, 0.0], "cornerRadius": 0.0,
                    "raycastBlock": False, "fillAmount": fill, "fillDir": fill_dir},
    }


FULL = {"aMin": [0.0, 0.0], "aMax": [1.0, 1.0], "oMin": [0.0, 0.0], "oMax": [0.0, 0.0]}

for sc in SCENES:
    path = os.path.join(BASE, sc)
    d = json.load(open(path, encoding='utf-8'))
    ents = d['entities']
    ents[:] = [e for e in ents if not str(e.get('name', '')).startswith('DrawGauge')]
    try:
        hud = next(i for i, e in enumerate(ents) if e.get('name') == 'HudCanvas')
    except StopIteration:
        print(sc, ': HudCanvas なし、スキップ')
        continue

    root = ui_image('DrawGauge', 'textures/ui_gauge_dial_rgba.png',
                    {"aMin": [0.5, 0.5], "aMax": [0.5, 0.5],
                     "oMin": [110.0, -30.0], "oMax": [250.0, 110.0]},
                    3, [1.0, 1.0, 1.0, 1.0])
    root['parent'] = hud
    ents.append(root)
    gi = len(ents) - 1
    for name, tex, order, color, fdir in [
        ('DrawGaugeArcFF', 'textures/ui_gauge_arc_rgba.png', 4, [0.33, 0.85, 1.0, 0.95], 4),
        ('DrawGaugeArcRW', 'textures/ui_gauge_arc_rgba.png', 4, [0.72, 0.50, 1.0, 0.95], 5),
        ('DrawGaugeHand', 'textures/ui_gauge_hand_rgba.png', 5, [0.95, 0.97, 1.0, 1.0], 0),
    ]:
        e = ui_image(name, tex, dict(FULL), order, color, fdir, 0.0 if 'Arc' in name else 1.0)
        e['parent'] = gi
        ents.append(e)

    json.dump(d, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print(sc, 'ok (HudCanvas idx', hud, ')')
