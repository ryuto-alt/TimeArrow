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
from knobs import K  # noqa: E402  タイミング定数の単一の真実源

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
        prop("speed", "float", 5.0), prop("jumpSpeed", "float", 12.4),
        prop("gravity", "float", 40.0), prop("killY", "float", -4.0),
        prop("halfW", "float", 0.34), prop("halfHeight", "float", 0.55),
        prop("arrowSpeed", "float", 15.0), prop("arrowRange", "float", 18.0),
        prop("arrowHalf", "float", 0.1), prop("minSkip", "float", 2.0),
        prop("maxSkip", "float", 10.0), prop("maxDrawTime", "float", 3.0),
        prop("aimTurnSpeed", "float", 220.0), prop("climbSpeed", "float", 4.0),
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
                                        prop("hitScale", "float", 0.6)]))


def door(name, x, openT, closeT, base=0.0):
    frame = mesh(name + "Frame", "Gate_Frame", x, base + 2.0, 1.1, 4.0, 1.0)
    grill = mesh(name, "Gate_Grill", x, base + 1.8, 0.75, 3.6, 1.0, shader=TIMEWARP,
                 lua=script("TimedDoor.lua", [
                     prop("openT", "float", float(openT)), prop("closeT", "float", float(closeT)),
                     prop("slideTime", "float", 0.7),
                     prop("listenButton", "bool", False)]))
    return [frame, grill]


def riseplat(name, x, y, sx, sy, arriveT, waitHeight, riseTime, trigger="", reverse=False):
    return mesh(name, "Bridge_Plank", x, y, sx, sy, 1.0, shader=TIMEWARP,
                lua=script("RisePlatform.lua", [
                    prop("arriveT", "float", float(arriveT)), prop("riseTime", "float", float(riseTime)),
                    prop("waitHeight", "float", float(waitHeight)), prop("triggerName", "string", trigger),
                    prop("listenButton", "bool", False),
                    prop("reverse", "bool", bool(reverse))]))


def pendulum(name, x, y, s, period, amplitude, phase, deadly=True):
    # Saw_Bladeは水平モデルなのでX軸90°回転で縦刃にする
    return mesh(name, "Saw_Blade", x, y, s, s, 0.5, shader=TIMEWARP, rot=(90.0, 0.0, 0.0),
                lua=script("Pendulum.lua", [
                    prop("period", "float", float(period)), prop("amplitude", "float", float(amplitude)),
                    prop("startPhase", "float", float(phase)), prop("deadly", "bool", bool(deadly)),
                    prop("hitScale", "float", 0.68)]))


def rollball(name, x, y, s, rollT, speed):
    return mesh(name, "Roll_Ball", x, y, s, s, s, shader=TIMEWARP,
                lua=script("RollBall.lua", [
                    prop("rollT", "float", float(rollT)), prop("rollSpeed", "float", float(speed)),
                    prop("axisX", "float", 1.0), prop("goalName", "string", "Exit"),
                    prop("goalHitScale", "float", 1.3), prop("hitScale", "float", 0.7)]))


def bomb(name, x, y, boomT, wallTarget="", blastScale=2.4):
    # Bomb_Orb: 底面y=-0.45/天面y=+0.81(導火線)なので y=床上+0.45 で置く
    return mesh(name, "Bomb_Orb", x, y, 1.0, 1.0, 1.0, shader=TIMEWARP,
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
    return mesh(name, "Target_Bull", x, y, s, s, 0.5, shader=TIMEWARP,
                lua=script("TargetGlow.lua", []))


def vine(name, x, bottomY, height, growT, growDur=1.0):
    return mesh(name, "Vine", x, bottomY + height * 0.5, 1.0, height, 1.0,
                lua=script("GrowVine.lua", [
                    prop("growT", "float", float(growT)),
                    prop("growDuration", "float", float(growDur)),
                    prop("bottomY", "float", float(bottomY)),
                    prop("unitHeight", "float", 1.0)]))


def crushwall(name, x, y, sx, sy, startT, axisX, speed, travel, ghostTime=1.4):
    return mesh(name, "Link_Wall", x, y, sx, sy, 1.0, shader=TIMEWARP,
                lua=script("CrushWall.lua", [
                    prop("startT", "float", float(startT)), prop("axisX", "float", float(axisX)),
                    prop("speed", "float", float(speed)), prop("travel", "float", float(travel)),
                    prop("ghostTime", "float", float(ghostTime)),
                    prop("materializeTime", "float", 0.25),
                    prop("listenButton", "bool", False), prop("startActive", "bool", True)]))


def ferry(name, x, y, period, amplitude, phase):
    # 乗れる横行フェリー(Pendulum.lua deadly=false)
    return mesh(name, "Move_Block", x, y, 2.4, 0.5, 1.0, shader=TIMEWARP,
                lua=script("Pendulum.lua", [
                    prop("period", "float", float(period)), prop("amplitude", "float", float(amplitude)),
                    prop("startPhase", "float", float(phase)), prop("deadly", "bool", False),
                    prop("hitScale", "float", 0.8)]))


def moveplat(name, x, y, period, amplitude, phase=0.0, sx=2.4):
    # 縦に往復する昇降足場(MovingPlatform.lua)。FFで位相を手繰り寄せて乗る
    return mesh(name, "Move_Block", x, y, sx, 0.5, 1.0, shader=TIMEWARP,
                lua=script("MovingPlatform.lua", [
                    prop("period", "float", float(period)),
                    prop("amplitude", "float", float(amplitude)),
                    prop("startPhase", "float", float(phase))]))


def fan(name, x, y, liftH=3.0, surgeH=7.0):
    base = mesh(name, "Fan_Base", x, y + 0.28, 1.0, 1.0, 1.0, shader=TIMEWARP,
                lua=script("Fan.lua", [
                    prop("bladesName", "string", name + "Blades"),
                    prop("liftHeight", "float", float(liftH)),
                    prop("surgeHeight", "float", float(surgeH)),
                    prop("strength", "float", 70.0),
                    prop("surgePerSkip", "float", 0.8),
                    prop("zoneHalfW", "float", 0.9)]))
    blades = mesh(name + "Blades", "Fan_Blades", x, y + 0.42, 1.0, 1.0, 1.0)
    return [base, blades]


def crumble(name, x, y, sx=1.6, crumbleT=1.6):
    return mesh(name, "Crumble_Plank", x, y, sx, 0.45, 1.0, shader=TIMEWARP,
                lua=script("CrumblePlatform.lua", [prop("crumbleT", "float", float(crumbleT))]))


def hammer(name, x, pivotY, s=1.0, period=3.2, maxAngle=55.0, phase=0.0, decayT=25.0):
    # 経年劣化3段階(新品/摩耗/錆)。HammerSwingが年齢でモデルを切り替える
    body = mesh(name, "Hammer_Age1", x, pivotY, s, s, 1.0, shader=TIMEWARP,
                lua=script("HammerSwing.lua", [
                    prop("period", "float", float(period)), prop("maxAngle", "float", float(maxAngle)),
                    prop("startPhase", "float", float(phase)), prop("decayT", "float", float(decayT)),
                    prop("hitHalf", "float", 0.42)]))
    mid = mesh(name + "_m2", "Hammer_Age2", x, -100.0, s, s, 1.0, shader=TIMEWARP)
    old = mesh(name + "_m3", "Hammer_Age3", x, -100.0, s, s, 1.0, shader=TIMEWARP)
    proxy = {"name": name + "X", "transform": transform(x, pivotY - 1.3 * s, 2.2 * s, 2.9 * s)}
    return [body, mid, old, proxy]


def turret(name, x, y, period=2.4, shotSpeed=6.0, rng=14.0, phase=0.0):
    t = mesh(name, "Turret", x, y, 1.0, 1.0, 1.0, shader=TIMEWARP,
             lua=script("Turret.lua", [
                 prop("period", "float", float(period)), prop("shotSpeed", "float", float(shotSpeed)),
                 prop("range", "float", float(rng)), prop("startPhase", "float", float(phase))]))
    shots = [mesh(f"{name}_p{i}", "Cannonball", 0, -100, 0.55, 0.55, 0.55)
             for i in (1, 2, 3)]
    return [t] + shots


def lattice(name, x, y=1.8):
    return mesh(name, "Gate_Grill", x, y, 0.75, 3.6, 1.0,
                lua=script("Lattice.lua", [prop("listenButton", "bool", True),
                                           prop("hideY", "float", -100.0)]))


def button(name, x, y, link):
    return mesh(name, "Button", x, y, 0.9, 0.9, 0.9, shader=TIMEWARP,
                lua=script("Button.lua", [
                    prop("linkTarget", "string", link), prop("standOn", "bool", False),
                    prop("arrowHit", "bool", True), prop("skipAmount", "float", 0.0)]))


def beacon(target_name, color=(1.0, 0.8, 0.2, 0.9), offset=1.2):
    return sprite("Beacon_" + target_name, "textures/arrow_rgba.png", 0, -100, 0.55, 0.28,
                  layer=8, color=color, rot_z=-90.0,
                  lua=script("Beacon.lua", [prop("targetName", "string", target_name),
                                            prop("offsetY", "float", float(offset)),
                                            prop("bob", "float", 0.15)]))


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

    # プレイヤー追従カメラ(dist13=視界約22u)+ TAB長押しで全景俯瞰(fit()で逆算)
    cam = copy.deepcopy(T["GameCamera"])
    x0, x1, y0, y1 = content_box(entities)
    VIEW_HW = 11.1
    min_x, max_x = x0 + VIEW_HW, max(x0 + VIEW_HW, x1 - VIEW_HW)
    fx, fy, fz, _ = fit(x0 - 0.5, x1 + 0.5, y0, y1 + 0.4, 14.0)
    pl = next(e for e in entities if e["name"] == "Player")
    px, py = pl["transform"]["position"][0], pl["transform"]["position"][1]
    cam["transform"]["position"] = [min(max(px, min_x), max_x), max(5.85, py + 5.3), -13.0]
    cam["transform"]["rotation"] = [14.0, 0.0, 0.0]
    cam["luaScript"] = script("CameraFollow.lua", [
        prop("dist", "float", 13.0), prop("offsetY", "float", 5.3),
        prop("minX", "float", round(min_x, 2)), prop("maxX", "float", round(max_x, 2)),
        prop("minY", "float", 5.85), prop("smooth", "float", 6.0),
        prop("fullX", "float", round(fx, 2)), prop("fullY", "float", round(fy, 2)),
        prop("fullZ", "float", round(fz, 2))])

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

# トゲ帯: 平地に置く幅1.6のトゲ。飛び越え必須(跳距離2.9に余裕)=「意味のあるトゲ」
def patch(pfx, xa, xb, nw=0.9):
    mid = (xa + xb) / 2
    return [needle(f"{pfx}N", mid, 0.3, 1.6, 0.6)]


# ══ 大型化レイアウト(2026-07-22 v3)══════════════════════════════════
# 各ステージ2〜4フェーズ構成。時間knobは tools/knobs.py の K を参照(単一の真実源)。
# 層: 地上=床上0 / デッキ=床上4.4(スラブy4.15) / 最上層=床上8.8(スラブy8.55)

S1, S2, S3, S4 = K["s1"], K["s2"], K["s3"], K["s4"]
S5, S6, S7, S8 = K["s5"], K["s6"], K["s7"], K["s8"]

# ── STAGE 1「遅すぎる橋・二連」(幅45) ────────────────────────────────
build(1, [
    gm(1, S1["limit"]),
    player(1.0, 0.55, targets="Bridge1,Bridge2", standables="Bridge1,Bridge2",
           arrowStops="FloorA,FloorB,FloorC", solids="FloorA,FloorB,FloorC",
           rewindShots=S1["rw"]),
    copy.deepcopy(arrow),
    exit_(43.0, 0.65, "scenes/stage2.json"), gate(43.0, 0.5),
    block("FloorA", 7.0, -0.5, 14.0, 1.0),        # [0,14]
    riseplat("Bridge1", 17.0, -0.3, 6.0, 0.6, arriveT=0.0, waitHeight=6.0,
             riseTime=S1["rise1"]),                # 橋を直接撃つ(FF=降ろす/RW=戻す)
    beacon("Bridge1"),
    block("FloorB", 25.0, -0.5, 10.0, 1.0),       # [20,30]
    riseplat("Bridge2", 33.0, -0.3, 6.0, 0.6, arriveT=0.0, waitHeight=6.0,
             riseTime=S1["rise2"], reverse=True),   # 上がって消えていく橋: Qで引き戻す
    beacon("Bridge2"),
    block("FloorC", 40.5, -0.5, 9.0, 1.0),        # [36,45]
], limit=S1["limit"], width=45)

# ── STAGE 2「四枚の閉門回廊」(幅52) ──────────────────────────────────
# 全ての門が目の前で閉まる。RW3発では4枚に足りない→最低1枚は「走って」間に合わせる。
# 道中: ハンマー(タイミング)/タレット弾幕(スロモで抜ける)/崩れ橋(急いで渡る or 戻す)
build(2, [
    gm(2, S2["limit"]),
    player(0.8, 0.55, targets="GateA,GateB,GateC,GateD,Ham2,Ham2X,Tur2,CrA2,CrB2",
           standables="CrA2,CrB2",
           arrowStops="F2a,F2b",
           solids="F2a,F2b,GateA,GateB,GateC,GateD",
           rewindShots=S2["rw"]),
    copy.deepcopy(arrow),
    exit_(49.5, 0.65, "scenes/stage3.json"), gate(49.5, 0.5),
    block("F2a", 19.25, -0.5, 38.5, 1.0),         # [0,38.5]
    block("F2b", 47.25, -0.5, 9.5, 1.0),          # [42.5,52] 間は奈落
    patch("P2a", 5.0, 6.7, 0.7),
    patch("P2b", 10.0, 11.7, 0.7),
    door("GateA", 14.6, openT=0.0, closeT=S2["closeA"]),      # スラム(RW)
    hammer("Ham2", 17.6, 3.5, 1.2, period=3.0, maxAngle=50.0),
    door("GateB", 24.0, openT=0.0, closeT=S2["closeB"]),      # 走れば間に合う
    turret("Tur2", 33.0, 1.0, period=2.6, shotSpeed=6.0, rng=11.0),
    patch("P2c", 27.0, 28.7, 0.7),
    door("GateC", 35.5, openT=0.0, closeT=S2["closeC"]),
    crumble("CrA2", 39.6, 0.2, 1.6, 1.6),         # 崩れ橋(奈落[38.5,42.5]の上)
    crumble("CrB2", 41.5, 0.2, 1.6, 1.6),
    door("GateD", 45.0, openT=0.0, closeT=S2["closeD"]),
], limit=S2["limit"], width=52)

# ── STAGE 3「風の谷」(幅58) ──────────────────────────────────
# 門は1枚だけ。主役は【橋(FF)】と【上昇気流ファン(FFサージ)】と【崩れ足場】。
# 谷1は自然には架からない橋 → FF。谷2は地上ルート皆無 → ファンでしか棚に上がれない。
# 棚の途中は崩れ足場(渡り切るか、RWで復活させるか)。最後の閉門はRWでしか開かない。
build(3, [
    gm(3, S3["limit"]),
    player(0.8, 0.55, targets="Bridge3,Fan3,CrA3,CrB3,GateZ3",
           standables="Bridge3,CrA3,CrB3",
           arrowStops="F3a,StepA3,StepB3,F3b,L3a,L3b,F3c",
           solids="F3a,StepA3,StepB3,F3b,L3a,L3b,F3c,Fan3,GateZ3",
           rewindShots=S3["rw"]),
    copy.deepcopy(arrow),
    exit_(54.0, 0.65, "scenes/stage4.json"), gate(54.0, 0.5),
    block("F3a", 10.5, -0.5, 21.0, 1.0),          # [0,21]
    patch("P3a", 3.0, 4.6),
    block("StepA3", 6.6, 0.6, 1.1, 1.2),          # 射撃台(橋を早撃ちする高台)
    block("StepB3", 7.8, 0.85, 1.1, 1.7),
    riseplat("Bridge3", 24.0, -0.3, 6.0, 0.6, arriveT=0.0, waitHeight=6.0,
             riseTime=S3["rise3"]),                # 谷1[21,27]: 自然降下は間に合わない
    beacon("Bridge3"),
    block("F3b", 32.0, -0.5, 10.0, 1.0),          # [27,37]
    fan("Fan3", 30.0, 0.0, liftH=2.6, surgeH=7.6),  # 谷2は地上ルート無し=サージ必須
    beacon("Fan3", color=(0.4, 0.9, 1.0, 0.95), offset=1.1),
    block("L3a", 34.5, 5.15, 6.0, 0.5),           # 棚[31.5,37.5](上面5.4)
    crumble("CrA3", 38.6, 5.175, 1.6, 1.5),       # 谷2[37,44]の上の崩れ足場
    crumble("CrB3", 40.4, 5.175, 1.6, 1.5),
    block("L3b", 44.4, 5.15, 6.0, 0.5),           # 棚[41.4,47.4]
    block("F3c", 51.0, -0.5, 14.0, 1.0),          # [44,58]
    door("GateZ3", 50.0, openT=0.0, closeT=S3["closeZ"]),     # 到着時には必ず閉じている
], limit=S3["limit"], width=58)

# ── STAGE 4「昇降の工房」(幅64) ────────────────────────────────
# 門は2枚だけ(スラムA=RW教材 / 錠Z=種まき教材)。主役は【乗り物】:
# 横に振れるフェリー(位相合わせ)と縦に往復する昇降足場(FFで手繰り寄せて乗る)。
# 途中に刃ピット/ハンマー(平地で唯一渡れる刃)/崩れ足場。
build(4, [
    gm(4, S4["limit"]),
    player(0.8, 0.55, targets="GateA4,Saw4,Ham4,Ham4X,Ferry4,Elev4,Lock4,CrA4,CrB4",
           standables="Ferry4,Elev4,CrA4,CrB4",
           arrowStops="F4a,PitF4,F4b,F4c,L4a,L4b",
           solids="F4a,PitF4,F4b,F4c,L4a,L4b,GateA4,Lock4", rewindShots=S4["rw"]),
    copy.deepcopy(arrow),
    exit_(62.5, 5.55, "scenes/stage5.json"), gate(62.5, 5.4),
    block("F4a", 9.4, -0.5, 18.8, 1.0),           # [0,18.8]
    block("PitF4", 19.4, -1.5, 1.2, 1.0),         # 刃の退避ピット
    block("F4b", 25.5, -0.5, 11.0, 1.0),          # [20,31]
    patch("P4a", 4.0, 5.7, 0.7),
    patch("P4b", 8.8, 10.4, 0.7),
    door("GateA4", 13.0, openT=0.0, closeT=S4["slamA"]),
    pendulum("Saw4", 19.4, 1.3, 1.4, period=4.0, amplitude=1.0, phase=0.0),
    hammer("Ham4", 27.0, 3.5, 1.2, period=3.4, maxAngle=55.0),
    ferry("Ferry4", 35.0, 0.35, period=S4["ferryP"], amplitude=3.2, phase=0.0),
    beacon("Ferry4", color=(0.4, 0.8, 1.0, 0.9), offset=0.8),   # 谷[31,39]を渡す
    block("F4c", 44.5, -0.5, 11.0, 1.0),          # [39,50]
    door("Lock4", 49.0, openT=S4["lockZ"], closeT=9999.0),      # x39から水平に種まき
    moveplat("Elev4", 51.5, 2.85, period=S4["elevP"], amplitude=2.3, phase=S4["elevPh"], sx=2.0),
    beacon("Elev4", color=(0.4, 0.8, 1.0, 0.9), offset=0.7),    # 谷[50,64]の唯一の足がかり
    block("L4a", 55.2, 5.15, 4.0, 0.5),           # レッジ[53.2,57.2](上面5.4)
    crumble("CrA4", 58.0, 5.175, 1.6, 1.5),       # 谷の上の崩れ足場(S3の再演)
    crumble("CrB4", 59.8, 5.175, 1.6, 1.5),
    block("L4b", 62.3, 5.15, 3.4, 0.5),           # [60.6,64]
], limit=S4["limit"], width=64)

# ── STAGE 5「時の昇降機・改」(幅88, 3層) ─────────────────────────────
# P1リフト昇降 → P2デッキ: 大玉チェイス(ピットからRWで背後へ送る)+錠D種まき
# → P3地上→ツタ(FF)→最上層: フェリー→閉門Y(サンド)→錠Z→出口
build(5, [
    gm(5, S5["limit"]),
    player(0.8, 0.55, targets="Lift5,Gate5,Ball5,LockD5,Vine5,Ferry5,GateY5,LockZ5,CrA5,CrB5",
           standables="Lift5,Ferry5,CrA5,CrB5", climbables="Vine5",
           arrowStops="F5a,F5b,StepA5,StepB5,D5a,PitR1F,D5b,PitR2F,D5c,T5a,T5b,Sill5",
           solids="F5a,F5b,StepA5,StepB5,D5a,PitR1F,D5b,PitR2F,D5c,T5a,T5b,Sill5,"
                  "Gate5,LockD5,GateY5,LockZ5", rewindShots=S5["rw"]),
    copy.deepcopy(arrow),
    exit_(85.5, 9.45, "scenes/stage6.json"), gate(85.5, 9.3),
    block("F5a", 27.0, -0.5, 54.0, 1.0),          # [0,54]
    block("F5b", 73.5, -0.5, 29.0, 1.0),          # [59,88] 間は奈落
    crumble("CrA5", 55.2, 0.2, 1.6, 1.6),
    crumble("CrB5", 57.2, 0.2, 1.6, 1.6),
    block("StepA5", 4.2, 0.6, 1.1, 1.2),
    needle("N5", 4.9, 0.2, 0.6, 0.4),
    block("StepB5", 5.6, 0.85, 1.1, 1.7),
    riseplat("Lift5", 12.5, -0.2, 3.0, 0.5, arriveT=S5["lift"], waitHeight=4.3, riseTime=1.0),
    block("D5a", 22.0, 3.75, 12.0, 0.5),          # デッキ[16,28]
    block("Sill5", 34.0, 1.6, 0.9, 3.2),          # デッキ支柱=地上バイパス封鎖
    block("PitR1F", 28.6, 2.55, 1.2, 0.5),        # 退避ピット1(上面2.8)
    block("D5b", 34.6, 3.75, 10.8, 0.5),          # [29.2,40]
    block("PitR2F", 40.6, 2.55, 1.2, 0.5),        # 退避ピット2
    block("D5c", 46.6, 3.75, 10.8, 0.5),          # [41.2,52]
    door("Gate5", 17.2, openT=0.0, closeT=S5["slamG"], base=4.0),
    rollball("Ball5", 19.5, 4.75, 1.5, rollT=S5["ballRoll"], speed=S5["ballSpeed"]),
    door("LockD5", 46.0, openT=S5["lockD"], closeT=9999.0, base=4.0),
    vine("Vine5", 61.2, bottomY=0.0, height=8.9, growT=S5["vineGrow"], growDur=1.2),
    beacon("Vine5", color=(0.4, 1.0, 0.5, 0.9), offset=0.8),
    block("T5a", 66.0, 8.55, 8.0, 0.5),           # 最上層[62,70]
    ferry("Ferry5", 72.0, 8.55, period=S5["ferryP"], amplitude=2.2, phase=0.0),
    block("T5b", 81.0, 8.55, 14.0, 0.5),          # [74,88]
    door("GateY5", 76.5, openT=0.0, closeT=S5["closeY"], base=8.8),
    door("LockZ5", 82.0, openT=S5["lockZ"], closeT=9999.0, base=8.8),
], limit=S5["limit"], width=88)

# ── STAGE 6「導火線と気流」(幅96, 2層) ───────────────────────────
# 門は終錠1枚だけ。RW教材は【逆橋】(上がって消える橋をQで引き戻す)、
# 高所へは【ファンのサージ】、レッジ上の詰みは【錆びついた動く壁】(FFで一瞬だけ実体が薄れる)。
# 支柱Sill6でレッジ下の地上バイパスを封鎖=レッジ経由が必須。
build(6, [
    gm(6, S6["limit"]),
    player(0.8, 0.55, targets="RevB6,Bomb6,Fan6,Bomb62,CW6,LockZ6,Ham6,Ham6X,Tur6",
           standables="RevB6",
           arrowStops="F6a,F6b,WallW6,WallW62,L6,Sill6",
           solids="F6a,F6b,WallW6,WallW62,L6,Sill6,Fan6,CW6,LockZ6,Tur6",
           rewindShots=S6["rw"]),
    copy.deepcopy(arrow),
    exit_(92.0, 0.65, "scenes/stage7.json"), gate(92.0, 0.5),
    block("F6a", 8.0, -0.5, 16.0, 1.0),           # [0,16]
    patch("P6a", 4.4, 6.1, 0.7),
    patch("P6b", 9.4, 11.0, 0.7),
    patch("P6x", 13.0, 14.6, 0.7),
    riseplat("RevB6", 18.25, -0.3, 4.5, 0.6, arriveT=0.0, waitHeight=6.0,
             riseTime=S6["rev6"], reverse=True),   # 谷[16,20.5]: 着く頃には上がりきっている
    beacon("RevB6"),
    block("F6b", 58.25, -0.5, 75.5, 1.0),         # [20.5,96]
    bomb("Bomb6", 24.0, 0.45, boomT=S6["boom1"], wallTarget="WallW6"),
    beacon("Bomb6", color=(1.0, 0.5, 0.2, 0.9), offset=0.9),
    breakwall("WallW6", 25.0, 1.7, 0.9, 3.4),     # 爆破しないとファンに近づけない
    fan("Fan6", 29.0, 0.0, liftH=2.4, surgeH=6.6),
    beacon("Fan6", color=(0.4, 0.9, 1.0, 0.95), offset=1.1),
    block("L6", 47.25, 4.15, 33.5, 0.5),          # レッジ[30.5,64](上面4.4)
    block("Sill6", 32.5, 2.0, 0.9, 4.0),          # レッジ下の地上バイパスを封鎖
    bomb("Bomb62", 44.0, 4.85, boomT=S6["boom2"], wallTarget="WallW62"),
    beacon("Bomb62", color=(1.0, 0.5, 0.2, 0.9), offset=0.9),
    breakwall("WallW62", 45.4, 6.0, 0.9, 3.2),    # レッジ上=登ってからしか撃てない
    crushwall("CW6", 52.0, 5.9, 1.0, 3.0, startT=S6["cwStart"], axisX=1.0,
              speed=1.0, travel=0.0, ghostTime=1.6),   # 錆びて止まった壁=FFの一瞬だけ抜ける
    patch("P6c", 68.0, 69.7, 0.7),
    hammer("Ham6", 70.5, 3.5, 1.2, period=3.2, maxAngle=55.0),
    patch("P6d", 73.0, 74.7, 0.7),
    door("LockZ6", 80.0, openT=S6["lockZ"], closeT=9999.0),   # 降りてからx66-70で種まき
    turret("Tur6", 86.5, 1.0, period=2.8, shotSpeed=6.0, rng=12.0),
], limit=S6["limit"], width=96)

# ── STAGE 7「時計塔大回廊」(幅104, 3層) ──────────────────────────────
# 地上東進→階段→デッキ西進(刃リズム2種+錠D)→塔上ボタン(デッキからのみ射線)
# →格子L1が開く→地上東進→ツタ(FF)→最上層東進(刃3)→錠Z種まき→出口
build(7, [
    gm(7, S7["limit"]),
    player(1.4, 0.55, targets="RevB7,LockD7,Button1,Saw7a,Saw7b,Saw7c,Vine7,LockZ7,Ham7a,Ham7aX,Ham7b,Ham7bX",
           climbables="Vine7", standables="RevB7",
           arrowStops="F7,F7a,Tower1,Baffle7,D7a,D7b,D7c,Pit1F,Pit2F,"
                      "St7a,St7b,St7c,St7d,T7a,T7b,Pit3F",
           solids="F7,F7a,Tower1,Baffle7,D7a,D7b,D7c,Pit1F,Pit2F,"
                  "St7a,St7b,St7c,St7d,T7a,T7b,Pit3F,LockD7,LatticeL1,LockZ7",
           rewindShots=S7["rw"]),
    copy.deepcopy(arrow),
    exit_(101.5, 9.45, "scenes/stage8.json"), gate(101.5, 9.3),
    block("F7a", 6.0, -0.5, 12.0, 1.0),           # [0,12]
    riseplat("RevB7", 14.25, -0.3, 4.5, 0.6, arriveT=0.0, waitHeight=6.0,
             riseTime=S7["rev7"], reverse=True),   # 谷[12,16.5]: 開幕のRW教材(門ではない)
    beacon("RevB7"),
    block("F7", 60.25, -0.5, 87.5, 1.0),          # [16.5,104]
    block("Tower1", 17.0, 3.5, 0.8, 3.0),   # 宙浮き[2,5]: 下を歩いてくぐれる
    block("Baffle7", 15.5, 3.95, 0.6, 1.9),  # 地上からの45°ズル射撃を遮る浮き石
    button("Button1", 17.0, 5.45, "LatticeL1"),
    beacon("Button1", color=(1.0, 0.35, 0.3, 0.95), offset=0.9),
    patch("P7a", 3.4, 5.0, 0.7),
    patch("P7b", 7.2, 8.8, 0.7),
    patch("P7c", 10.0, 11.6, 0.7),
    block("D7a", 27.75, 4.15, 20.5, 0.5),         # デッキ[17.5,38]
    block("Pit1F", 38.8, 3.15, 1.6, 0.5),         # 刃ピット1
    block("D7b", 44.8, 4.15, 10.4, 0.5),          # [39.6,50]
    block("Pit2F", 50.8, 3.15, 1.6, 0.5),         # 刃ピット2
    block("D7c", 57.45, 4.15, 11.7, 0.5),         # [51.6,63.3] 階段へ接続
    pendulum("Saw7a", 38.8, 5.7, 1.4, period=S7["sawP1"], amplitude=1.2, phase=0.0),
    pendulum("Saw7b", 50.8, 5.7, 1.4, period=S7["sawP2"], amplitude=1.0, phase=0.0),
    door("LockD7", 22.0, openT=S7["lockD"], closeT=9999.0, base=4.4),
    hammer("Ham7a", 30.0, 3.9, 1.2, period=3.4, maxAngle=50.0),
    hammer("Ham7b", 44.0, 3.9, 1.2, period=2.6, maxAngle=50.0, phase=1.1),
    block("St7a", 62.3, 0.55, 0.7, 1.1),
    block("St7b", 63.0, 1.1, 0.7, 2.2),
    block("St7c", 63.7, 1.65, 0.7, 3.3),
    block("St7d", 64.4, 2.2, 0.7, 4.4),
    lattice("LatticeL1", 68.5),
    vine("Vine7", 72.5, bottomY=0.0, height=8.9, growT=S7["vineGrow"], growDur=1.2),
    beacon("Vine7", color=(0.4, 1.0, 0.5, 0.9), offset=0.8),
    block("T7a", 80.0, 8.55, 12.0, 0.5),          # 最上層[74,86]
    block("Pit3F", 86.8, 7.55, 1.6, 0.5),         # 刃ピット3(上面7.8)
    block("T7b", 95.9, 8.55, 16.2, 0.5),          # [87.6,104]
    pendulum("Saw7c", 86.8, 10.1, 1.4, period=S7["sawP3"], amplitude=1.0, phase=0.0),
    door("LockZ7", 98.0, openT=S7["lockZ"], closeT=9999.0, base=8.8),
], limit=S7["limit"], width=104)

# ── STAGE 8「時計職人の卒業試験」(幅120, 3層5フェーズ) ────────────
# 門は2枚だけ(開幕スラム=RW / 終盤の錠E=種まき)。それ以外は今まで習った道具の総ざらい:
# 爆弾で壁を割る→ファンでデッキへ→圧力爆弾の圏内で種まき→刃ピット→ハンマー→
# 逆橋→フェリー→リフトに乗ってRWで最上層→大玉レース+砲台→崩れ足場→
# 格子越しにボタンを撃つ→出口。(大玉はS5の主役なのでS8では使わない)
build(8, [
    gm(8, S8["limit"]),
    player(0.8, 0.55,
           targets="GateA8,Bomb8,Fan8,BombF8,LockE8,SawB8,Ham8,Ham8X,RevB8,Ferry8,"
                   "Lift8,Tur8,CrA8,CrB8,Button8",
           standables="RevB8,Ferry8,Lift8,CrA8,CrB8",
           arrowStops="F8a,WallW8,D8a,Sill8,PitS8F,F8b,F8c,F8d,T8a,T8b",
           solids="F8a,WallW8,D8a,Sill8,PitS8F,F8b,F8c,F8d,T8a,T8b,"
                  "GateA8,LockE8,Fan8,Tur8,LatticeL8",
           rewindShots=S8["rw"]),
    copy.deepcopy(arrow),
    exit_(117.0, 9.45, "scenes/game_clear.json"), gate(117.0, 9.3),

    # ── P1 地上: スラム門(RW) → 爆弾で壁を割る → ファンでデッキへ ──
    block("F8a", 12.0, -0.5, 24.0, 1.0),          # [0,24]
    patch("P8a", 4.0, 5.4, 0.5),
    patch("P8b", 8.0, 9.4, 0.5),
    door("GateA8", 12.2, openT=0.0, closeT=S8["slamA"]),
    bomb("Bomb8", 15.2, 0.45, boomT=S8["boomB"], wallTarget="WallW8"),
    beacon("Bomb8", color=(1.0, 0.5, 0.2, 0.9), offset=0.9),
    breakwall("WallW8", 16.2, 1.6, 0.9, 3.2),
    fan("Fan8", 20.5, 0.0, liftH=2.4, surgeH=6.6),
    beacon("Fan8", color=(0.4, 0.9, 1.0, 0.95), offset=1.1),

    # ── P2 デッキ[22,44]: 圧力爆弾の圏内で終錠に種まき → 刃ピット ──
    block("D8a", 33.0, 4.15, 22.0, 0.5),          # デッキ(上面4.4)
    block("Sill8", 24.0, 2.0, 0.9, 4.0),          # 地上バイパス封鎖
    bomb("BombF8", 29.0, 4.85, boomT=S8["boomF"], wallTarget=""),   # 壁なし=純粋な圧力
    beacon("BombF8", color=(1.0, 0.5, 0.2, 0.9), offset=0.9),
    door("LockE8", 33.0, openT=S8["lockE"], closeT=9999.0, base=4.4),
    block("PitS8F", 38.5, 3.15, 1.6, 0.5),        # 刃の退避ピット
    pendulum("SawB8", 38.5, 5.7, 1.4, period=4.0, amplitude=1.0, phase=0.0),

    # ── P3 地上[24,56]: ハンマー → 逆橋(RW) → フェリー ──
    block("F8b", 40.0, -0.5, 32.0, 1.0),          # [24,56]
    patch("P8c", 46.0, 47.4, 0.5),
    hammer("Ham8", 49.5, 3.5, 1.2, period=3.0, maxAngle=55.0),
    patch("P8d", 52.0, 53.4, 0.5),
    riseplat("RevB8", 58.25, -0.3, 4.5, 0.6, arriveT=0.0, waitHeight=6.0,
             riseTime=S8["rev8"], reverse=True),   # 谷[56,60.5]
    beacon("RevB8"),
    block("F8c", 66.25, -0.5, 11.5, 1.0),         # [60.5,72]
    ferry("Ferry8", 76.0, 0.35, period=S8["ferryP"], amplitude=3.2, phase=0.0),
    beacon("Ferry8", color=(0.4, 0.8, 1.0, 0.9), offset=0.8),       # 谷[72,80]

    # ── P4 リフトに乗ってRWで最上層へ ──
    block("F8d", 86.0, -0.5, 12.0, 1.0),          # [80,92] この先は奈落=リフト必須
    riseplat("Lift8", 86.0, -0.2, 3.0, 0.5, arriveT=S8["lift"], waitHeight=8.75,
             riseTime=1.2),           # 待機高=最上層と面一(隙間なく乗り移れる)
    beacon("Lift8", color=(0.4, 0.8, 1.0, 0.9), offset=0.8),

    # ── P5 最上層[88,120]: 大玉レース+砲台 → 崩れ足場 → 格子越しにボタン ──
    block("T8a", 95.75, 8.55, 16.5, 0.5),         # [87.5,104](上面8.8)=リフト右端と接する
    turret("Tur8", 102.0, 9.4, period=3.2, shotSpeed=5.5, rng=13.0),
    crumble("CrA8", 104.8, 8.575, 1.6, 1.5),      # 谷[104,107.4]
    crumble("CrB8", 106.6, 8.575, 1.6, 1.5),
    block("T8b", 113.7, 8.55, 12.6, 0.5),         # [107.4,120]
    lattice("LatticeL8", 110.0, 10.6),            # 矢は素通り/プレイヤーは通れない
    button("Button8", 113.0, 9.7, "LatticeL8"),   # 格子の向こう側=撃つしかない
    beacon("Button8", color=(1.0, 0.35, 0.3, 0.95), offset=0.9),
], limit=S8["limit"], width=120)

# ── ギミックラボ(stage0: 新ギミック実機検証用。セレクト未登録)─────────
build(0, [
    gm(0, 120),
    player(1.0, 0.55, targets="LabFan,LabCrumble,LabHammer,LabHammerX,LabTurret",
           standables="LabCrumble",
           arrowStops="LabF,LabLedge", solids="LabF,LabLedge,LabTurret,LabFan", rewindShots=9),
    copy.deepcopy(arrow),
    exit_(34.0, 0.65, "scenes/title.json"), gate(34.0, 0.5),
    block("LabF", 18.0, -0.5, 36.0, 1.0),
    fan("LabFan", 5.0, 0.0, liftH=2.5, surgeH=6.5),
    block("LabLedge", 8.2, 5.4, 2.4, 0.5),        # サージでしか届かない棚
    crumble("LabCrumble", 12.5, 2.2, 1.6, 1.6),
    hammer("LabHammer", 17.0, 3.6, 1.2, period=3.2, maxAngle=55.0),
    turret("LabTurret", 30.0, 1.0, period=2.4, shotSpeed=6.0, rng=12.0),
], limit=120, width=36)

# ── 検証: JSON再読込 + parent整合 + スラム門の最速到達チェック ─────────
WALK, HOPJ = 5.0, 0.15
SLAMS = {
    2: (14.6, K["s2"]["closeA"], 2, 0.8),
    4: (13.0, K["s4"]["slamA"], 2, 0.8),
    8: (12.2, K["s8"]["slamA"], 2, 0.8),
}
for n in range(1, 9):
    s = json.load(open(os.path.join(SCENES, f"stage{n}.json"), encoding="utf-8"))
    names = [e["name"] for e in s["entities"]]
    # Playerの参照リスト(targets/solids等)の全名が実在するか(カンマ欠落・消し忘れ検出)
    pl = next(e for e in s["entities"] if e["name"] == "Player")
    plprops = {q["name"]: q["value"] for q in pl["luaScript"]["props"]}
    for key in ("targets", "standables", "climbables", "arrowStops", "solids"):
        for nm in filter(None, [x.strip() for x in plprops.get(key, "").split(",")]):
            assert nm in names, f"stage{n}: {key} に実在しない名前 '{nm}'"
    for e in s["entities"]:
        if "parent" in e:
            assert names[e["parent"]] == "HudCanvas", (n, e["name"])
    assert "PlayerMarker" in names
    if n in SLAMS:
        gx, ct, hops, sx = SLAMS[n]
        fastest = (gx - sx) / WALK + hops * HOPJ
        assert fastest > ct + 0.15, f"stage{n}: スラム最速到達{fastest:.2f} <= 閉{ct}(+0.15)"
        print(f"  stage{n} スラム検証: 最速{fastest:.2f}s > 閉{ct}s ✓")
print("all 8 scenes valid")
