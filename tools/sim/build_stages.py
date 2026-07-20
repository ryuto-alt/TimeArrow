"""ステージ1-5のジオメトリ/ギミックを宣言データから組み立ててシーンJSONへ書き戻す.

既存シーンの GameManager / Player / Arrow / 背景 / カメラ / HUD(UICanvas配下)はそのまま残し、
地形とギミックだけを差し替える。parent はエンティティ配列のインデックス参照なので、
名前で解決し直してから書き出す。

物理定数(すべてのステージ共通・Player.lua の既定と一致):
    speed 5.0 / jumpSpeed 11.6 / gravity 40.0 / halfW 0.4 / halfHeight 0.55
      → 最高到達(足元) 1.68 / 滞空 0.58秒 / 水平到達 2.90 / 越えられる穴幅 3.7
    設計ルール: 越えさせない穴は 4.2以上 / 越えさせる穴は 3.0以下
                 登らせない段差は 2.0以上 / 登らせる段差は 1.4以下
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENES = ROOT / "assets" / "scenes"

MODELS = {
    "block": "models/Block/Block.obj",
    "plank": "models/Bridge_Plank/Bridge_Plank.obj",
    "move": "models/Move_Block/Move_Block.obj",
    "button": "models/Button/Button.obj",
    "target": "models/Target_Bull/Target_Bull.obj",
    "vine": "models/Vine/Vine.obj",
    "saw": "models/Saw_Blade/Saw_Blade.obj",
    "door": "models/Timed_Door/Timed_Door.obj",
    "ball": "models/Roll_Ball/Roll_Ball.obj",
    "needle": "models/Needle_Small/Needle_Small.obj",
    "wall": "models/Link_Wall/Link_Wall.obj",
}

PLAYER_BASE = [
    ("speed", "float", 5.0), ("jumpSpeed", "float", 11.6), ("gravity", "float", 40.0),
    ("killY", "float", -4.0), ("halfW", "float", 0.4), ("halfHeight", "float", 0.55),
    ("arrowSpeed", "float", 15.0), ("arrowRange", "float", 18.0), ("arrowHalf", "float", 0.1),
    ("minSkip", "float", 2.0), ("maxSkip", "float", 10.0), ("maxDrawTime", "float", 3.0),
    ("aimTurnSpeed", "float", 270.0), ("climbSpeed", "float", 4.0),
]


def ent(name, model, pos, scale, script=None, props=None, rot=(0, 0, 0), rough=0.6):
    e = {
        "material": {"metallic": 0.05, "roughness": rough},
        "meshRenderer": {"modelPath": MODELS[model]},
        "name": name,
        "transform": {"position": list(pos), "rotation": list(rot), "scale": list(scale)},
    }
    if script:
        e["luaScript"] = {
            "enabled": True,
            "props": [{"name": n, "type": t, "value": v} for (n, t, v) in (props or [])],
            "scriptPath": f"scripts/{script}",
        }
    return e


def floor(name, x0, x1, top=0.0, thick=1.0):
    """[x0, x1] を覆う床。上面が top になるように配置する。"""
    return ent(name, "block", ((x0 + x1) / 2, top - thick / 2, 0.0), (x1 - x0, thick, 3.0))


def ledge(name, x0, x1, top, thick=0.5, model="plank"):
    return ent(name, model, ((x0 + x1) / 2, top - thick / 2, 0.0), (x1 - x0, thick, 1.0))


def btn(name, pos, link, skip=12.0, scale=0.9):
    return ent(name, "target", pos, (scale, scale, 0.5), "Button.lua", [
        ("linkTarget", "string", link), ("standOn", "bool", False),
        ("arrowHit", "bool", True), ("skipAmount", "float", skip)])


def lift(name, x0, x1, top, thick=0.5, arrive=11.0):
    """矢を当てるまで現れないせり上がり足場。arriveT は制限時間(10秒)より後。"""
    e = ledge(name, x0, x1, top, thick)
    e["luaScript"] = {"enabled": True, "scriptPath": "scripts/RisePlatform.lua", "props": [
        {"name": "arriveT", "type": "float", "value": arrive},
        {"name": "riseTime", "type": "float", "value": 0.35},
        {"name": "hideY", "type": "float", "value": -100.0},
        {"name": "triggerName", "type": "string", "value": ""},
        {"name": "listenButton", "type": "bool", "value": False}]}
    return e


def needle(name, x0, x1, y=0.2):
    return ent(name, "needle", ((x0 + x1) / 2, y, 0.0), (x1 - x0, 0.4, 1.0), "Wall.lua",
               [("deadly", "bool", True), ("hitScale", "float", 0.75)])


# --------------------------------------------------------------------------
# ステージ定義
# --------------------------------------------------------------------------
STAGES = {}

# ---- STAGE 1: 落とし穴に橋を架ける(矢1射のチュートリアル) -------------------
# 床 X0..7 / 穴 X7..12(幅5=絶対に跳べない) / 床 X12..16
STAGES["stage1"] = dict(
    player=(1.0, 0.55), exit_x=15.0, camera=(8.0, 4.6, -12.4),
    solids=["FloorL", "FloorR"],
    stands=["Bridge1"],
    targets=["Target1"],
    stops=["FloorL", "FloorR"],
    climbs=[],
    entities=[
        floor("FloorL", 0.0, 7.0),
        floor("FloorR", 12.0, 16.0),
        # 橋の上面は床とツライチ(0.0)。段差があると standable は横から乗れず落ちる
        lift("Bridge1", 7.0, 12.0, 0.0, thick=0.6),
        btn("Target1", (9.5, 3.2, 0.0), "Bridge1"),
    ],
)

# ---- STAGE 2: 蔦を伸ばして登る → 矢を回収 → 遮蔽ボタンを横撃ちで橋 ----------
# 地上は X0..6 だけ。その先は一面の奈落で、ゴールは高台の上にある。
STAGES["stage2"] = dict(
    player=(1.0, 0.55), exit=(15.0, 5.65), camera=(8.0, 5.4, -13.6),
    solids=["FloorL", "Ledge2", "Ledge3"],
    stands=["Bridge2"],
    targets=["VineBtn", "Button2"],
    stops=["FloorL", "Ledge2", "Ledge3"],
    climbs=["Vine1"],
    entities=[
        floor("FloorL", 0.0, 6.0),
        # 蔦: growT=11 なので制限時間内には自然に育たない。矢でしか伸びない
        ent("Vine1", "vine", (3.0, 2.75, 0.0), (0.8, 5.5, 0.8), "GrowVine.lua", [
            ("growT", "float", 11.0), ("growDuration", "float", 0.4),
            ("bottomY", "float", 0.0), ("unitHeight", "float", 1.0)]),
        btn("VineBtn", (3.0, 5.2, 0.0), "Vine1"),
        # Ledge2 は Button2 の真下を完全に覆う。地上や跳躍中からの斜め射線は
        # 必ずこの板に刺さるので、板の上まで登って水平に撃つしかない
        ledge("Ledge2", 4.0, 9.4, 4.45),
        btn("Button2", (8.6, 5.2, 0.0), "Bridge2", scale=0.8),
        # Ledge2(支持端9.8)から Ledge3(支持端13.6)は3.8マス=跳べない。橋が要る
        lift("Bridge2", 9.6, 13.8, 5.0, thick=0.4),
        ledge("Ledge3", 14.0, 16.0, 5.0, thick=0.4),
    ],
)

# ---- STAGE 3: 針の海をリフト2枚で渡る(矢を途中で回収する2射) -----------------
# 床 X0..5 / 針の奈落 X5..12.5 / 床 X12.5..16。リフト1枚では対岸に届かない
STAGES["stage3"] = dict(
    player=(1.0, 0.55), exit_x=15.0, camera=(8.0, 5.0, -13.0),
    solids=["FloorL", "FloorR", "Step3"],
    stands=["Lift3a", "Lift3b"],
    targets=["Btn3a", "Btn3b"],
    stops=["FloorL", "FloorR", "Step3"],
    climbs=[],
    entities=[
        floor("FloorL", 0.0, 5.0),
        floor("FloorR", 12.5, 16.0),
        needle("Needle3", 5.0, 12.5),
        ledge("Step3", 3.2, 5.0, 1.4, thick=1.4, model="block"),
        # Lift3b は Step3(支持端5.4)から3.8マス離す。3.7マスを超えないと
        # 「Btn3b だけ撃って跳び移る」矢1本ショートカットが通ってしまう
        lift("Lift3a", 5.5, 7.5, 1.4, thick=0.4),
        lift("Lift3b", 9.6, 11.8, 1.4, thick=0.4),
        btn("Btn3a", (6.5, 4.0, 0.0), "Lift3a"),
        btn("Btn3b", (10.7, 4.0, 0.0), "Lift3b"),
    ],
)

# ---- STAGE 4: 迫る壁を至近で撃ってすり抜け(矢は即回収)→ 時間窓ドアを射抜く --
# 床 X1..16 のみ。壁に押されて X1 より左へ出ると奈落。
STAGES["stage4"] = dict(
    player=(2.0, 0.55), exit_x=15.8, camera=(8.5, 5.0, -13.0),
    solids=["Floor4", "Wall4", "Door4"],
    stands=[],
    targets=["Wall4", "Door4"],
    stops=["Floor4"],
    climbs=[],
    entities=[
        floor("Floor4", 1.0, 16.0),
        ent("Wall4", "wall", (13.0, 4.0, 0.0), (1.2, 8.0, 1.0), "CrushWall.lua", [
            ("startT", "float", 0.0), ("axisX", "float", -1.0), ("speed", "float", 1.3),
            ("travel", "float", 12.0), ("ghostTime", "float", 0.6),
            ("materializeTime", "float", 0.25), ("listenButton", "bool", False),
            ("startActive", "bool", True)], rough=0.5),
        # openT=11 は制限時間の外。矢の引き量で開く時刻を手繰り寄せる(引きすぎると通り過ぎる)
        ent("Door4", "door", (15.0, 2.0, 0.0), (1.1, 4.0, 1.0), "TimedDoor.lua", [
            ("openT", "float", 11.0), ("closeT", "float", 14.0),
            ("sinkAmount", "float", 4.6), ("listenButton", "bool", False),
            ("deadly", "bool", False), ("hitScale", "float", 0.8)], rough=0.5),
    ],
)

# ---- STAGE 5: 天井から動く床で降りる(下は針の奈落)→ 時間窓ドアを射抜く ------
# 右半分は「天井付きのトンネル」。動く床が十分下がった位相でしか入口をくぐれず、
# トンネルの上を歩いて迂回することもできない(入口の柱が届かない高さまで伸びている)。
STAGES["stage5"] = dict(
    player=(1.5, 7.05), exit_x=14.5, camera=(8.0, 5.6, -14.0),
    solids=["CeilL5", "FloorR5", "Roof5", "Pillar5", "Door5"],
    stands=["MoveFloor5"],
    targets=["Door5"],
    stops=["CeilL5", "FloorR5", "Roof5", "Pillar5"],
    climbs=[],
    entities=[
        ledge("CeilL5", 0.0, 5.0, 6.5, thick=0.5),
        floor("FloorR5", 7.4, 16.0),
        needle("Needle5", 0.0, 7.4),
        # period5/振幅2.9: t=0 が上死点(天井とツライチ)、t=2.5 が下死点
        ent("MoveFloor5", "move", (5.95, 3.35, 0.0), (2.3, 0.5, 1.0), "MovingPlatform.lua", [
            ("period", "float", 5.0), ("amplitude", "float", 2.9),
            ("startPhase", "float", 1.25)]),
        # トンネルの天井(下面2.6)。床が下がりきった位相でしか入口をくぐれない
        ledge("Roof5", 7.6, 16.0, 3.4, thick=0.8, model="block"),
        # 天井の上を歩いて迂回されないよう、入口の柱を届かない高さまで伸ばす
        ent("Pillar5", "wall", (7.8, 7.7, 0.0), (0.4, 8.6, 1.0), rough=0.5),
        ent("Door5", "door", (11.0, 1.25, 0.0), (1.1, 2.5, 1.0), "TimedDoor.lua", [
            ("openT", "float", 11.0), ("closeT", "float", 14.0),
            ("sinkAmount", "float", 3.2), ("listenButton", "bool", False),
            ("deadly", "bool", False), ("hitScale", "float", 0.8)], rough=0.5),
    ],
)


# --------------------------------------------------------------------------
# 書き出し
# --------------------------------------------------------------------------
KEEP = {"GameManager", "Player", "Arrow", "Backdrop", "Sun", "GameCamera", "Grid",
        "Exit", "GoalGate"}


def is_ui(e):
    return any(k.startswith("ui") for k in e) or "parent" in e


def build(stage: str):
    spec = STAGES[stage]
    path = SCENES / f"{stage}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    old = data["entities"]

    # parent をインデックス→名前に退避
    for e in old:
        if "parent" in e:
            e["_parentName"] = old[e["parent"]]["name"]

    kept = [e for e in old if e["name"] in KEEP or is_ui(e)]
    by_name = {e["name"]: e for e in kept}

    # Player 位置と props
    px, py = spec["player"]
    by_name["Player"]["transform"]["position"] = [px, py, 0.0]
    props = list(PLAYER_BASE) + [
        ("targets", "string", ",".join(spec["targets"])),
        ("standables", "string", ",".join(spec["stands"])),
        ("climbables", "string", ",".join(spec["climbs"])),
        ("arrowStops", "string", ",".join(spec["stops"])),
        ("solids", "string", ",".join(spec["solids"])),
        ("mirrors", "string", ""),
    ]
    by_name["Player"]["luaScript"]["props"] = \
        [{"name": n, "type": t, "value": v} for (n, t, v) in props] + \
        [{"name": "maxBounces", "type": "int", "value": 4}]

    # ゴール
    ex, ey = spec["exit"] if "exit" in spec else (spec["exit_x"], 0.65)
    by_name["Exit"]["transform"]["position"] = [ex, ey, 0.0]
    if "GoalGate" in by_name:
        by_name["GoalGate"]["transform"]["position"] = [ex, ey - 0.15, 0.8]
    cx, cy, cz = spec["camera"]
    by_name["GameCamera"]["transform"]["position"] = [cx, cy, cz]

    # 地形/ギミックを差し替え。UI は末尾に固めて parent を貼り直す
    gameplay = [e for e in kept if not is_ui(e)]
    ui = [e for e in kept if is_ui(e)]
    new = gameplay + spec["entities"] + ui
    index = {e["name"]: i for i, e in enumerate(new)}
    for e in new:
        if "_parentName" in e:
            e["parent"] = index[e.pop("_parentName")]

    data["entities"] = new
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True),
                    encoding="utf-8")
    return len(new)


if __name__ == "__main__":
    for s in STAGES:
        print(f"{s}: {build(s)} エンティティ")
