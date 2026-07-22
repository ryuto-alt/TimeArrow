# -*- coding: utf-8 -*-
# TimeArrow ステージ1-8 全面再設計ジェネレータ(2026-07-22)。
# 設計値は tools/sim_stages.py で機械検証済み(矢なし/FFのみ/RWのみ不成立+マージン帯)。
# 共通部(Backdrop/Sun/Camera/Grid/HUD)は既存 stage2.json から流用。
# カメラは tools/sim/camera_fit.py の実装で全体が収まるよう逆算する。
#
# 物理: ジャンプ高1.68/滞空0.58s/移動5/矢速15/引き0.15-3s(+2〜+10)/構え中世界0.25倍
# 経済: FF=タイマー+量*0.5 / RW=実効量*0.5返金(回数制)
# 刃 : 平地の振り子ノコは絶対に通過不能(数値検証済) → 必ず退避ピット構造で使う
import json, copy, os, sys

SCENES = r"C:\Users\ryuto\game\TimeArrow\assets\scenes"
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sim"))
from camera_fit import content_box, fit  # noqa: E402

tpl = json.load(open(os.path.join(SCENES, "stage2.json"), encoding="utf-8"))
T = {e["name"]: e for e in tpl["entities"]}

TIMEWARP = "shaders/TimeWarp.hlsl"
FONT = "fonts/DotGothic16-400.ttf"


def prop(name, ptype, value):
    return {"name": name, "type": ptype, "value": value}


def transform(x, y, sx, sy, sz=1.0, z=0.0, rot=(0.0, 0.0, 0.0)):
    return {"position": [float(x), float(y), float(z)],
            "rotation": [float(rot[0]), float(rot[1]), float(rot[2])],
            "scale": [float(sx), float(sy), float(sz)]}


def script(path, props):
    return {"enabled": True, "props": props, "scriptPath": f"scripts/{path}"}


def mesh(name, model, x, y, sx, sy, sz=1.0, lua=None, rough=0.6, shader=None, rot=(0.0, 0.0, 0.0), z=0.0):
    e = {"material": {"metallic": 0.05, "roughness": rough},
         "meshRenderer": {"modelPath": f"models/{model}/{model}.obj"},
         "name": name, "transform": transform(x, y, sx, sy, sz, z=z, rot=rot)}
    if lua:
        e["luaScript"] = lua
    if shader:
        e["shader"] = shader
    return e


def sprite(name, tex, x, y, sx, sy, layer=5, lua=None, color=(1, 1, 1, 1), rot_z=0.0):
    return {"name": name,
            "transform": transform(x, y, sx, sy, rot=(0.0, 0.0, float(rot_z))),
            "sprite2d": {"billboard": False, "color": list(map(float, color)),
                         "effectValue": 0.0, "layer": layer, "shaderAlphaBlend": False,
                         "shaderParams": [0.0, 0.0, 0.0, 0.0], "shaderPath": "",
                         "size": [1.0, 1.0], "texturePath": tex,
                         "uvMax": [1.0, 1.0], "uvMin": [0.0, 0.0], "worldSpace": True},
            **({"luaScript": lua} if lua else {})}


def gm(n, limit):
    e = copy.deepcopy(T["GameManager"])
    e["luaScript"]["props"] = [prop("T", "float", float(limit)),
                              prop("scenePath", "string", f"scenes/stage{n}.json"),
                              prop("title", "string", f"STAGE {n}"),
                              prop("markers", "string", "")]
    return e


def player(x, y, targets="", standables="", climbables="", arrowStops="", solids="", rewindShots=3):
    e = copy.deepcopy(T["Player"])
    e["transform"]["position"] = [float(x), float(y), 0.0]
    # 視認性: 見た目だけ1割強拡大(当たり判定 halfW/halfHeight は据え置き=寛容側)
    e["transform"]["scale"] = [0.9, 1.2, 1.0]
    e["luaScript"]["props"] = [
        prop("speed", "float", 5.0), prop("jumpSpeed", "float", 11.6),
        prop("gravity", "float", 40.0), prop("killY", "float", -4.0),
        prop("halfW", "float", 0.4), prop("halfHeight", "float", 0.55),
        prop("arrowSpeed", "float", 15.0), prop("arrowRange", "float", 18.0),
        prop("arrowHalf", "float", 0.1), prop("minSkip", "float", 2.0),
        prop("maxSkip", "float", 10.0), prop("maxDrawTime", "float", 3.0),
        prop("aimTurnSpeed", "float", 270.0), prop("climbSpeed", "float", 4.0),
        prop("targets", "string", targets), prop("standables", "string", standables),
        prop("climbables", "string", climbables), prop("arrowStops", "string", arrowStops),
        prop("solids", "string", solids), prop("mirrors", "string", ""),
        prop("maxBounces", "int", 4), prop("rewindShots", "int", int(rewindShots)),
    ]
    return e


def exit_(x, y, nxt):
    e = copy.deepcopy(T["Exit"])
    e["transform"]["position"] = [float(x), float(y), 0.0]
    e["luaScript"]["props"] = [prop("radius", "float", 1.2), prop("next", "string", nxt)]
    return e


def gate(x, y):
    e = copy.deepcopy(T["GoalGate"])
    e["transform"]["position"] = [float(x), float(y), 0.8]
    return e


def block(name, x, y, sx, sy, sz=3.0):
    return mesh(name, "Block", x, y, sx, sy, sz)


def needle(name, x, y, sx, sy):
    return mesh(name, "Needle_Small", x, y, sx, sy, 1.0,
                lua=script("Wall.lua", [prop("deadly", "bool", True),
                                        prop("hitScale", "float", 0.75)]))


def door(name, x, openT, closeT, base=0.0):
    frame = mesh(name + "Frame", "Gate_Frame", x, base + 2.0, 1.1, 4.0, 1.0)
    grill = mesh(name, "Gate_Grill", x, base + 1.8, 0.75, 3.6, 1.0,
                 lua=script("TimedDoor.lua", [
                     prop("openT", "float", float(openT)), prop("closeT", "float", float(closeT)),
                     prop("slideTime", "float", 0.7),
                     prop("listenButton", "bool", False)]))
    return [frame, grill]


def riseplat(name, x, y, sx, sy, arriveT, waitHeight, riseTime, trigger=""):
    return mesh(name, "Bridge_Plank", x, y, sx, sy, 1.0, shader=TIMEWARP,
                lua=script("RisePlatform.lua", [
                    prop("arriveT", "float", float(arriveT)), prop("riseTime", "float", float(riseTime)),
                    prop("waitHeight", "float", float(waitHeight)), prop("triggerName", "string", trigger),
                    prop("listenButton", "bool", False)]))


def pendulum(name, x, y, s, period, amplitude, phase, deadly=True):
    # Saw_Bladeは水平モデルなのでX軸90°回転で縦刃にする
    return mesh(name, "Saw_Blade", x, y, s, s, 0.5, shader=TIMEWARP, rot=(90.0, 0.0, 0.0),
                lua=script("Pendulum.lua", [
                    prop("period", "float", float(period)), prop("amplitude", "float", float(amplitude)),
                    prop("startPhase", "float", float(phase)), prop("deadly", "bool", bool(deadly)),
                    prop("hitScale", "float", 0.8)]))


def rollball(name, x, y, s, rollT, speed):
    return mesh(name, "Roll_Ball", x, y, s, s, s, shader=TIMEWARP,
                lua=script("RollBall.lua", [
                    prop("rollT", "float", float(rollT)), prop("rollSpeed", "float", float(speed)),
                    prop("axisX", "float", 1.0), prop("goalName", "string", "Exit"),
                    prop("goalHitScale", "float", 1.3), prop("hitScale", "float", 0.8)]))


def bomb(name, x, y, boomT, wallTarget="", blastScale=2.4):
    return sprite(name, "textures/bomb_rgba.png", x, y, 0.9, 0.9, layer=5,
                  lua=script("Bomb.lua", [
                      prop("boomT", "float", float(boomT)),
                      prop("blastScale", "float", float(blastScale)),
                      prop("wallTarget", "string", wallTarget)]))


def breakwall(name, x, y, sx, sy):
    e = mesh(name, "Block", x, y, sx, sy, 3.0, rough=0.9,
             lua=script("Wall.lua", [prop("deadly", "bool", False),
                                     prop("hitScale", "float", 0.8)]))
    e["material"]["metallic"] = 0.0
    return e


def target(name, x, y, s=1.3):
    return mesh(name, "Target_Bull", x, y, s, s, 0.5)


def lattice(name, x, y=1.8):
    return mesh(name, "Gate_Grill", x, y, 0.75, 3.6, 1.0,
                lua=script("Lattice.lua", [prop("listenButton", "bool", True),
                                           prop("hideY", "float", -100.0)]))


def button(name, x, y, link):
    return mesh(name, "Button", x, y, 0.9, 0.9, 0.9,
                lua=script("Button.lua", [
                    prop("linkTarget", "string", link), prop("standOn", "bool", False),
                    prop("arrowHit", "bool", True), prop("skipAmount", "float", 0.0)]))


def marker():
    return sprite("PlayerMarker", "textures/arrow_rgba.png", 1.5, 2.0, 0.6, 0.3, layer=8,
                  lua=script("PlayerMarker.lua", [prop("offsetY", "float", 1.35),
                                                 prop("bob", "float", 0.12)]),
                  color=(1.0, 0.85, 0.25, 0.9), rot_z=-90.0)


def ui_text(name, text, size, color, outline, rect):
    return {"name": name, "transform": transform(0, 0, 1, 1),
            "uiRect": {"anchorMax": rect["aMax"], "anchorMin": rect["aMin"],
                       "clipChildren": False, "offsetMax": rect["oMax"], "offsetMin": rect["oMin"],
                       "order": 2, "pivot": rect.get("pivot", [0.5, 0.5]),
                       "rotation": 0.0, "skewX": 0.0, "visible": True},
            "uiText": {"alignH": 1, "alignV": 1, "charAnim": 0, "charAnimAmount": 4.0,
                       "charAnimSpeed": 2.0, "color": color, "fontPath": FONT,
                       "fontSize": float(size), "gradientColor2": [1.0, 1.0, 1.0, 1.0],
                       "gradientDir": 0, "letterSpacing": 2.0, "outlineColor": outline,
                       "outlineWidth": 2.0, "rich": False, "shadowColor": [0.0, 0.0, 0.0, 0.6],
                       "shadowOffset": [2.0, 2.0], "text": text, "typewriterSpeed": 0.0,
                       "wrap": False}}


def build(n, entities, limit, width):
    flat = []
    for e in entities:
        (flat.extend if isinstance(e, list) else flat.append)(e)
    entities = flat + [marker()]

    backdrop = copy.deepcopy(T["Backdrop"])
    for pr in backdrop["luaScript"]["props"]:
        if pr["name"] == "T":
            pr["value"] = float(limit)
    backdrop["transform"]["position"][0] = width / 2.0
    backdrop["transform"]["position"][1] = width * 0.10
    backdrop["transform"]["scale"][0] = width * 2.32
    backdrop["transform"]["scale"][1] = width * 1.21

    # プレイヤー追従カメラ(dist9.5で視界約16u幅=旧16幅ステージと同じプレイヤーサイズ)
    cam = copy.deepcopy(T["GameCamera"])
    x0, x1, y0, y1 = content_box(entities)
    VIEW_HW = 8.1
    min_x, max_x = x0 + VIEW_HW, max(x0 + VIEW_HW, x1 - VIEW_HW)
    pl = next(e for e in entities if e["name"] == "Player")
    px, py = pl["transform"]["position"][0], pl["transform"]["position"][1]
    cam["transform"]["position"] = [min(max(px, min_x), max_x), max(4.9, py + 4.35), -9.5]
    cam["transform"]["rotation"] = [14.0, 0.0, 0.0]
    cam["luaScript"] = script("CameraFollow.lua", [
        prop("dist", "float", 9.5), prop("offsetY", "float", 4.35),
        prop("minX", "float", round(min_x, 2)), prop("maxX", "float", round(max_x, 2)),
        prop("minY", "float", 4.9), prop("smooth", "float", 6.0)])

    sun = copy.deepcopy(T["Sun"])
    sun["transform"]["position"][0] = width / 2.0

    ents = entities + [backdrop, sun, cam, copy.deepcopy(T["Grid"]),
                       copy.deepcopy(T["HudCanvas"])]
    hud_i = len(ents) - 1
    seek = copy.deepcopy(T["SeekBar"])
    seek["uiSlider"]["maxValue"] = float(limit)
    banner = ui_text("TimeBanner", f"{int(limit)}秒以内にゴールしろ！", 44,
                     [1.0, 0.85, 0.3, 1.0], [0.05, 0.1, 0.25, 1.0],
                     {"aMin": [0.0, 0.0], "aMax": [1.0, 0.0],
                      "oMin": [0.0, 26.0], "oMax": [0.0, 120.0], "pivot": [0.5, 0.0]})
    tleft = ui_text("TimeLeft", f"{limit:.1f}", 34,
                    [1.0, 1.0, 1.0, 1.0], [0.05, 0.1, 0.25, 1.0],
                    {"aMin": [1.0, 0.0], "aMax": [1.0, 0.0],
                     "oMin": [-180.0, 26.0], "oMax": [-16.0, 80.0], "pivot": [1.0, 0.0]})
    draw_amt = ui_text("DrawAmount", "", 38,
                       [0.4, 0.9, 1.0, 1.0], [0.05, 0.1, 0.25, 1.0],
                       {"aMin": [0.0, 0.0], "aMax": [1.0, 0.0],
                        "oMin": [0.0, 140.0], "oMax": [0.0, 200.0], "pivot": [0.5, 0.0]})
    rw_cnt = ui_text("RewindCount", "まき戻し ×0", 26,
                     [0.75, 0.55, 1.0, 1.0], [0.05, 0.1, 0.25, 1.0],
                     {"aMin": [0.0, 0.0], "aMax": [0.0, 0.0],
                      "oMin": [16.0, 26.0], "oMax": [300.0, 78.0], "pivot": [0.0, 0.0]})
    for child in (seek, copy.deepcopy(T["ScreenFlash"]), banner, tleft, draw_amt, rw_cnt):
        child["parent"] = hud_i
        ents.append(child)
    scene = {k: copy.deepcopy(v) for k, v in tpl.items() if k != "entities"}
    scene["entities"] = ents
    path = os.path.join(SCENES, f"stage{n}.json")
    json.dump(scene, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    cp = cam["transform"]["position"]
    print(f"stage{n}: {len(ents)} entities, followCam clamp=[{min_x:.1f},{max_x:.1f}] start=({cp[0]:.1f},{cp[1]:.1f})")


arrow = copy.deepcopy(T["Arrow"])

# 針山パッチ: 段1.2→段1.7の二段ホップで越える(段差<=1.35/隙間<=2.0を厳守)
def patch(pfx, xa, xb, nw=0.9):
    mid = (xa + xb) / 2
    return [block(f"{pfx}L", xa, 0.6, 1.1, 1.2),
            needle(f"{pfx}N", mid, 0.2, nw, 0.4),
            block(f"{pfx}R", xb, 0.85, 1.1, 1.7)]


# ══ STAGE 1「遅すぎる橋」 15s / RW1 (幅33) ═══════════════════════════
build(1, [
    gm(1, 15),
    player(1.0, 0.55, targets="Target1", standables="Bridge1",
           arrowStops="FloorL,FloorR", solids="FloorL,FloorR", rewindShots=1),
    copy.deepcopy(arrow),
    exit_(31.0, 0.65, "scenes/stage2.json"), gate(31.0, 0.5),
    block("FloorL", 10.0, -0.5, 20.0, 1.0),
    block("FloorR", 30.5, -0.5, 5.0, 1.0),
    riseplat("Bridge1", 24.0, -0.3, 8.0, 0.6, arriveT=0.0, waitHeight=6.0, riseTime=15.0,
             trigger="Target1"),
    target("Target1", 24.0, 6.8, 1.3),   # 撃つ的: x16-18から45°射線上。当てると橋の時計が進む
], limit=15, width=33)

# ══ STAGE 2「二枚の閉門」 16s / RW2 (幅28) ═══════════════════════════
build(2, [
    gm(2, 16),
    player(0.8, 0.55, targets="GateA,GateB",
           arrowStops="F2,P2aL,P2aR,P2bL,P2bR,P2cL,P2cR",
           solids="F2,P2aL,P2aR,P2bL,P2bR,P2cL,P2cR,GateA,GateB", rewindShots=2),
    copy.deepcopy(arrow),
    exit_(25.8, 0.65, "scenes/stage3.json"), gate(25.8, 0.5),
    block("F2", 14.0, -0.5, 28.0, 1.0),
    patch("P2a", 4.6, 6.3, 0.7),
    patch("P2b", 9.0, 10.7, 0.7),
    door("GateA", 13.0, openT=0.0, closeT=2.8),
    patch("P2c", 16.4, 18.1, 0.7),
    door("GateB", 21.5, openT=0.0, closeT=6.0),
], limit=16, width=28)

# ══ STAGE 3「錠と門」 20s / RW1 (幅30) ═══════════════════════════════
build(3, [
    gm(3, 20),
    player(0.8, 0.55, targets="Lock3,Gate3",
           arrowStops="F3,StepA3,StepB3,P3aL,P3aR",
           solids="F3,StepA3,StepB3,P3aL,P3aR,Lock3,Gate3", rewindShots=1),
    copy.deepcopy(arrow),
    exit_(26.8, 0.65, "scenes/stage4.json"), gate(26.8, 0.5),
    block("F3", 15.0, -0.5, 30.0, 1.0),
    block("StepA3", 7.4, 0.6, 1.1, 1.2),
    block("StepB3", 8.6, 0.85, 1.1, 1.7),
    door("Lock3", 11.4, openT=22.0, closeT=9999.0),
    patch("P3a", 15.4, 17.0, 0.7),
    door("Gate3", 21.4, openT=0.0, closeT=1.5),
], limit=20, width=30)

# ══ STAGE 4「動かせない締切」 23s / RW2 (幅30) ═══════════════════════
build(4, [
    gm(4, 23),
    player(0.8, 0.55, targets="GateA4,Lock4,GateB4,Saw4",
           arrowStops="F4a,PitF4,F4b,P4aL,P4aR,P4bL,P4bR",
           solids="F4a,PitF4,F4b,P4aL,P4aR,P4bL,P4bR,GateA4,Lock4,GateB4", rewindShots=2),
    copy.deepcopy(arrow),
    exit_(28.6, 0.65, "scenes/stage5.json"), gate(28.6, 0.5),
    block("F4a", 9.4, -0.5, 18.8, 1.0),           # [0,18.8]
    block("PitF4", 19.4, -1.5, 1.2, 1.0),         # 退避ピット床(上面-1.0)
    block("F4b", 25.0, -0.5, 10.0, 1.0),          # [20,30]
    patch("P4a", 4.0, 5.7, 0.7),
    patch("P4b", 8.8, 10.4, 0.7),
    door("GateA4", 13.0, openT=0.0, closeT=2.6),
    door("Lock4", 15.4, openT=25.0, closeT=9999.0),
    pendulum("Saw4", 19.4, 1.3, 1.4, period=4.0, amplitude=1.0, phase=0.0),
    door("GateB4", 24.4, openT=0.0, closeT=15.0),
], limit=23, width=30)

# ══ STAGE 5「時の昇降機」 26s / RW3 (幅34) ═══════════════════════════
build(5, [
    gm(5, 26),
    player(0.8, 0.55, targets="Lift5,Gate5,Ball5,Lock5",
           standables="Lift5",
           arrowStops="F5,StepA5,StepB5,D5a,D5b,PitF5",
           solids="F5,StepA5,StepB5,D5a,D5b,PitF5,Gate5,Lock5", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(32.6, 4.65, "scenes/stage6.json"), gate(32.6, 4.5),
    block("F5", 17.0, -0.5, 34.0, 1.0),
    block("StepA5", 4.2, 0.6, 1.1, 1.2),
    needle("N5", 4.9, 0.2, 0.6, 0.4),
    block("StepB5", 5.6, 0.85, 1.1, 1.7),
    riseplat("Lift5", 12.5, -0.3, 3.0, 0.5, arriveT=14.0, waitHeight=4.3, riseTime=1.0),
    block("D5a", 20.0, 3.75, 8.0, 0.5),           # デッキ[16,24]
    block("PitF5", 24.6, 2.55, 1.2, 0.5),         # 退避ピット床(上面2.8)
    block("D5b", 29.6, 3.75, 8.8, 0.5),           # デッキ[25.2,34]
    door("Gate5", 17.2, openT=0.0, closeT=2.6, base=4.0),
    rollball("Ball5", 20.5, 4.75, 1.5, rollT=0.0, speed=0.55),
    door("Lock5", 30.4, openT=30.0, closeT=9999.0, base=4.0),
], limit=26, width=34)

# ══ STAGE 6「導火線」 30s / RW2 (幅34) ═══════════════════════════════
build(6, [
    gm(6, 30),
    player(0.8, 0.55, targets="GateA6,Bomb6,GateC6,Lock6",
           arrowStops="F6,P6aL,P6aR,P6bL,P6bR,P6cL,P6cR,WallW6",
           solids="F6,P6aL,P6aR,P6bL,P6bR,P6cL,P6cR,WallW6,GateA6,GateC6,Lock6",
           rewindShots=2),
    copy.deepcopy(arrow),
    exit_(32.0, 0.65, "scenes/stage7.json"), gate(32.0, 0.5),
    block("F6", 17.0, -0.5, 34.0, 1.0),
    patch("P6a", 4.4, 6.1, 0.7),
    patch("P6b", 9.4, 11.0, 0.7),
    door("GateA6", 13.6, openT=0.0, closeT=2.8),
    bomb("Bomb6", 17.6, 0.45, boomT=24.0, wallTarget="WallW6"),
    breakwall("WallW6", 18.6, 1.7, 0.9, 3.4),
    door("GateC6", 21.6, openT=0.0, closeT=12.0),
    patch("P6c", 23.6, 25.2, 0.7),
    door("Lock6", 27.6, openT=21.0, closeT=9999.0),
], limit=30, width=34)

# ══ STAGE 7「時計塔の往復」 36s / RW3 (幅31) ═════════════════════════
build(7, [
    gm(7, 36),
    player(1.4, 0.55, targets="GateA7,LockD7,ButtonB7,Saw7",
           arrowStops="F7,Tower7,P7aL,P7aR,P7bL,P7bR,WallE7,D7a,D7b,PitF7,St7a,St7b,St7c,St7d",
           solids="F7,Tower7,P7aL,P7aR,P7bL,P7bR,WallE7,D7a,D7b,PitF7,St7a,St7b,St7c,St7d,"
                  "GateA7,LockD7,LatticeL7", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(14.2, 0.65, "scenes/stage8.json"), gate(14.2, 0.5),
    block("F7", 15.5, -0.5, 31.0, 1.0),
    block("Tower7", 0.5, 3.1, 0.8, 6.2),
    button("ButtonB7", 0.5, 6.65, "LatticeL7"),
    patch("P7a", 3.4, 5.0, 0.7),
    patch("P7b", 7.2, 8.8, 0.7),
    door("GateA7", 11.4, openT=0.0, closeT=2.3),
    lattice("LatticeL7", 13.3),
    block("WallE7", 15.4, 1.95, 0.8, 3.9),
    block("St7a", 27.7, 0.55, 0.7, 1.1),
    block("St7b", 28.4, 1.1, 0.7, 2.2),
    block("St7c", 29.1, 1.65, 0.7, 3.3),
    block("St7d", 29.8, 2.2, 0.7, 4.4),
    block("D7a", 8.9, 4.15, 12.6, 0.5),           # デッキ[2.6,15.2]
    block("PitF7", 16.0, 3.15, 1.6, 0.5),         # デッキピット床(上面3.4)
    block("D7b", 23.0, 4.15, 12.4, 0.5),          # デッキ[16.8,29.2]
    pendulum("Saw7", 16.0, 5.7, 1.4, period=4.0, amplitude=1.2, phase=0.0),
    door("LockD7", 4.4, openT=26.0, closeT=9999.0, base=4.4),
], limit=36, width=31)

# ══ STAGE 8「時計職人の卒業試験」 38s / RW4 (幅36) ═══════════════════
build(8, [
    gm(8, 38),
    player(0.8, 0.55, targets="GateA8,Bomb8,GateC8,GateD8,BombF8,LockE8,BankSaw8",
           arrowStops="F8,P8aL,P8aR,P8bL,P8bR,WallW8,St8a,St8b,St8c,D8",
           solids="F8,P8aL,P8aR,P8bL,P8bR,WallW8,St8a,St8b,St8c,D8,"
                  "GateA8,GateC8,GateD8,LockE8", rewindShots=4),
    copy.deepcopy(arrow),
    exit_(33.4, 5.05, "scenes/game_clear.json"), gate(33.4, 4.9),
    block("F8", 18.0, -0.5, 36.0, 1.0),
    patch("P8a", 4.0, 5.4, 0.5),
    patch("P8b", 8.0, 9.4, 0.5),
    door("GateA8", 12.2, openT=0.0, closeT=2.6),
    bomb("Bomb8", 15.2, 0.45, boomT=26.0, wallTarget="WallW8"),
    breakwall("WallW8", 16.2, 1.6, 0.9, 3.2),
    door("GateC8", 18.6, openT=0.0, closeT=13.0),
    block("St8a", 20.6, 0.55, 0.7, 1.1),
    block("St8b", 21.3, 1.1, 0.7, 2.2),
    block("St8c", 22.0, 1.65, 0.7, 3.3),
    block("D8", 29.3, 4.15, 13.4, 0.5),           # デッキ[22.6,36]
    door("GateD8", 24.0, openT=0.0, closeT=10.5, base=4.4),
    bomb("BombF8", 31.0, 4.85, boomT=22.0, wallTarget=""),
    door("LockE8", 32.4, openT=36.0, closeT=9999.0, base=4.4),
    pendulum("BankSaw8", 19.0, 6.6, 1.8, period=4.0, amplitude=0.0, phase=0.0, deadly=False),
], limit=38, width=36)

# ── 検証: JSON再読込 + parent整合 + 閉門の最速到達チェック ─────────────
WALK, HOPJ = 5.0, 0.15
SLAMS = {  # stage: (gate x, closeT, 経路上のホップ数, スタートx)
    2: (13.0, 2.8, 5, 0.8), 4: (13.0, 2.6, 4, 0.8), 6: (13.6, 2.8, 4, 0.8),
    7: (11.4, 2.3, 4, 1.4), 8: (12.2, 2.6, 4, 0.8),
}
for n in range(1, 9):
    s = json.load(open(os.path.join(SCENES, f"stage{n}.json"), encoding="utf-8"))
    names = [e["name"] for e in s["entities"]]
    for e in s["entities"]:
        if "parent" in e:
            assert names[e["parent"]] == "HudCanvas", (n, e["name"])
    assert "PlayerMarker" in names and "RewindCount" in names
    if n in SLAMS:
        gx, ct, hops, sx = SLAMS[n]
        fastest = (gx - sx) / WALK + hops * HOPJ
        assert fastest > ct + 0.15, f"stage{n}: スラム最速到達{fastest:.2f} <= 閉{ct}(+0.15)"
        print(f"  stage{n} スラム検証: 最速{fastest:.2f}s > 閉{ct}s ✓")
print("all 8 scenes valid")
