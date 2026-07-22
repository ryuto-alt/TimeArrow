# -*- coding: utf-8 -*-
# TimeArrow ステージ1-5再設計ジェネレータ。
# 共通部(Backdrop/Sun/Camera/Grid/HUD/postProcess)は既存stage2.jsonから流用し、
# ステージ固有エンティティだけを組み立てる。設計値は物理シミュ済:
#   ジャンプ高1.68 / 滞空0.58s / 移動5/s / 矢15/s / 先送り2-10(引き0-3s) / 後戻り予算5s
import json, copy, os

SCENES = r"C:\Users\ryuto\game\TimeArrow\assets\scenes"
tpl = json.load(open(os.path.join(SCENES, "stage2.json"), encoding="utf-8"))
T = {e["name"]: e for e in tpl["entities"]}

def prop(name, ptype, value):
    return {"name": name, "type": ptype, "value": value}

def transform(x, y, sx, sy, sz=1.0, z=0.0, rot=(0.0, 0.0, 0.0)):
    return {"position": [float(x), float(y), float(z)],
            "rotation": [float(rot[0]), float(rot[1]), float(rot[2])],
            "scale": [float(sx), float(sy), float(sz)]}

def mesh(name, model, x, y, sx, sy, sz=1.0, lua=None, rough=0.6, shader=None, rot=(0.0, 0.0, 0.0)):
    e = {"material": {"metallic": 0.05, "roughness": rough},
         "meshRenderer": {"modelPath": f"models/{model}/{model}.obj"},
         "name": name, "transform": transform(x, y, sx, sy, sz, rot=rot)}
    if lua:
        e["luaScript"] = lua
    if shader:
        e["shader"] = shader
    return e

TIMEWARP = "shaders/TimeWarp.hlsl"

def script(path, props):
    return {"enabled": True, "props": props, "scriptPath": f"scripts/{path}"}

def gm(n, limit):
    e = copy.deepcopy(T["GameManager"])
    e["luaScript"]["props"] = [prop("T", "float", float(limit)),
                               prop("scenePath", "string", f"scenes/stage{n}.json"),
                               prop("title", "string", f"STAGE {n}"),
                               prop("markers", "string", "")]
    return e

def player(x, y, targets="", standables="", climbables="", arrowStops="", solids="", mirrors="", rewindShots=3):
    e = copy.deepcopy(T["Player"])
    e["transform"]["position"] = [float(x), float(y), 0.0]
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
        prop("solids", "string", solids), prop("mirrors", "string", mirrors),
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
    # 落とし格子門: 石フレーム(飾り) + 可動格子(実体・矢の的)。格子が物理的にスライドして開閉する。
    # base=設置面の高さ(2階の床上にも置ける)
    frame = mesh(name + "Frame", "Gate_Frame", x, base + 2.0, 1.1, 4.0, 1.0)
    grill = mesh(name, "Gate_Grill", x, base + 1.8, 0.75, 3.6, 1.0,
                 lua=script("TimedDoor.lua", [
                     prop("openT", "float", float(openT)), prop("closeT", "float", float(closeT)),
                     prop("slideTime", "float", 0.7),
                     prop("listenButton", "bool", False)]))
    return [frame, grill]

def riseplat(name, x, y, sx, sy, arriveT, trigger="", waitHeight=5.5, riseTime=0.9):
    return mesh(name, "Bridge_Plank", x, y, sx, sy, 1.0, shader=TIMEWARP,
                lua=script("RisePlatform.lua", [
                    prop("arriveT", "float", float(arriveT)), prop("riseTime", "float", float(riseTime)),
                    prop("waitHeight", "float", float(waitHeight)), prop("triggerName", "string", trigger),
                    prop("listenButton", "bool", False)]))

def moveplat(name, x, y, sx, sy, period, amplitude, phase):
    return mesh(name, "Move_Block", x, y, sx, sy, 1.0, shader=TIMEWARP,
                lua=script("MovingPlatform.lua", [
                    prop("period", "float", float(period)), prop("amplitude", "float", float(amplitude)),
                    prop("startPhase", "float", float(phase))]))

def pendulum(name, x, y, s, period, amplitude, phase):
    # Saw_Bladeモデルは水平置きなのでX軸90°回転で縦刃にする(当たり判定はscaleのAABBで不変)
    return mesh(name, "Saw_Blade", x, y, s, s, 0.5, shader=TIMEWARP, rot=(90.0, 0.0, 0.0),
                lua=script("Pendulum.lua", [
                    prop("period", "float", float(period)), prop("amplitude", "float", float(amplitude)),
                    prop("startPhase", "float", float(phase)), prop("deadly", "bool", True),
                    prop("hitScale", "float", 0.8)]))

def rollball(name, x, y, s, rollT, speed):
    return mesh(name, "Roll_Ball", x, y, s, s, s, shader=TIMEWARP,
                lua=script("RollBall.lua", [
                    prop("rollT", "float", float(rollT)), prop("rollSpeed", "float", float(speed)),
                    prop("axisX", "float", 1.0), prop("goalName", "string", "Exit"),
                    prop("goalHitScale", "float", 1.3), prop("hitScale", "float", 0.8)]))

def target(name, x, y, s):
    return mesh(name, "Target_Bull", x, y, s, s, 0.5)

FONT = "fonts/DotGothic16-400.ttf"

def ui_text(name, text, size, color, outline, rect):
    return {
        "name": name,
        "transform": transform(0, 0, 1, 1),
        "uiRect": {
            "anchorMax": rect["aMax"], "anchorMin": rect["aMin"],
            "clipChildren": False,
            "offsetMax": rect["oMax"], "offsetMin": rect["oMin"],
            "order": 2, "pivot": rect.get("pivot", [0.5, 0.5]),
            "rotation": 0.0, "skewX": 0.0, "visible": True},
        "uiText": {
            "alignH": 1, "alignV": 1, "charAnim": 0,
            "charAnimAmount": 4.0, "charAnimSpeed": 2.0,
            "color": color, "fontPath": FONT, "fontSize": float(size),
            "gradientColor2": [1.0, 1.0, 1.0, 1.0], "gradientDir": 0,
            "letterSpacing": 2.0,
            "outlineColor": outline, "outlineWidth": 2.0,
            "rich": False,
            "shadowColor": [0.0, 0.0, 0.0, 0.6], "shadowOffset": [2.0, 2.0],
            "text": text, "typewriterSpeed": 0.0, "wrap": False}}

def rewind_bar():
    e = copy.deepcopy(T["SeekBar"])
    e["name"] = "RewindBar"
    e["uiRect"]["offsetMin"] = [0.0, -26.0]
    e["uiRect"]["offsetMax"] = [0.0, -18.0]
    e["uiSlider"].update({
        "maxValue": 5.0, "value": 5.0,
        "fillColor": [0.55, 0.35, 1.0, 1.0],
        "knobColor": [0.75, 0.55, 1.0, 1.0],
        "trackColor": [1.0, 1.0, 1.0, 0.18]})
    return e

def build(n, entities, limit=10.0):
    flat = []
    for e in entities:
        (flat.extend if isinstance(e, list) else flat.append)(e)
    entities = flat
    backdrop = copy.deepcopy(T["Backdrop"])
    for pr in backdrop["luaScript"]["props"]:
        if pr["name"] == "T":
            pr["value"] = float(limit)
    ents = entities + [backdrop, copy.deepcopy(T["Sun"]),
                       copy.deepcopy(T["GameCamera"]), copy.deepcopy(T["Grid"]),
                       copy.deepcopy(T["HudCanvas"])]
    hud_i = len(ents) - 1
    seek = copy.deepcopy(T["SeekBar"])
    seek["uiSlider"]["maxValue"] = float(limit)
    # UIはY軸下向き(anchor y=0が上端)。バナーは上部センター、残り時間は右上
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
    rw_cnt = ui_text("RewindCount", "まき戻し ×3", 26,
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
    print(f"stage{n}: {len(ents)} entities -> {path}")

arrow = copy.deepcopy(T["Arrow"])

# ══ 時間経済版レベルデザイン(8ステージ) ═══════════════════════════════════
# ★数値は tools/sim_stages.py で機械検証済み: 全ステージ「矢なしクリア不能」+想定プランのマージン正常。
# 経済: 先送り=タイマー+量*0.5 / 後戻り=実効量*0.5返金(回数制)。ギミック時計は実時間で進む。
# 弓矢必須の3構造: ①開錠>制限(FF必須) ②閉門<最速到達(RW必須) ③錠前→実時間締切のサンド(FF必須)

# ── STAGE 1「時は金なり」(制限12/戻し1) 橋の自然落下14秒>制限 → FF必須 ──────
# 矢なし: 着橋14→タイマー15.8で死。FF+12(代償6): 実8でゴール、タイマー10.2(マージン1.8)
build(1, [
    gm(1, 12),
    player(1.0, 0.55, targets="Target1", standables="Bridge1",
           arrowStops="FloorL,FloorR", solids="FloorL,FloorR", rewindShots=1),
    copy.deepcopy(arrow),
    exit_(15.0, 0.65, "scenes/stage2.json"), gate(15.0, 0.5),
    block("FloorL", 3.5, -0.5, 7.0, 1.0),
    block("FloorR", 14.0, -0.5, 4.0, 1.0),
    riseplat("Bridge1", 9.5, -0.3, 5.0, 0.6, arriveT=0.0, trigger="Target1",
             waitHeight=6.0, riseTime=14.0),
    target("Target1", 6.0, 4.5, 1.1),
], limit=12)

# ── STAGE 2「二枚の閉門」(制限9/戻し3) 閉1.5/3.0 < 最速到達1.8/4.1 → RW必須 ──
# 開始直後に目の前でガシャン→「もう閉まった!?」→紫の矢で呼び戻す、を2回。
build(2, [
    gm(2, 9),
    player(1.0, 0.55, targets="GateA,GateB",
           arrowStops="Floor2,StepA,StepB",
           solids="Floor2,StepA,StepB,GateA,GateB", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(15.0, 0.65, "scenes/stage3.json"), gate(15.0, 0.5),
    block("Floor2", 8.0, -0.5, 16.0, 1.0),
    needle("Needle2", 4.8, 0.2, 3.6, 0.4),
    block("StepA", 3.7, 0.6, 1.1, 1.2),
    block("StepB", 5.4, 0.85, 1.1, 1.7),
    door("GateA", 8.0, openT=0.0, closeT=1.5),
    door("GateB", 12.0, openT=0.0, closeT=3.0),
], limit=9)

# ── STAGE 3「錠前と締切のサンド」(制限13/戻し2) 錠開10→閉門閉9 → FF必須 ──────
# 待つと錠前通過が実10>閉門9で構造的に手遅れ。錠前へFF+8.6で実1.4に開け、
# 刃(周期4)を捌いて実5.5に閉門を通過。余った後戻りは刃に-8の銀行(位相不変で返金4)。
build(3, [
    gm(3, 13),
    player(0.8, 0.55, targets="LockGate3,Blade3,ClosingGate3",
           arrowStops="Floor3,StepA3,StepB3,StepE3",
           solids="Floor3,StepA3,StepB3,StepE3,LockGate3,ClosingGate3", rewindShots=2),
    copy.deepcopy(arrow),
    exit_(15.4, 0.65, "scenes/stage4.json"), gate(15.4, 0.5),
    block("Floor3", 8.0, -0.5, 16.0, 1.0),
    needle("Needle3", 3.75, 0.2, 2.5, 0.4),
    block("StepA3", 3.2, 0.6, 1.1, 1.2),
    block("StepB3", 4.4, 0.85, 1.1, 1.7),
    door("LockGate3", 6.0, openT=10.0, closeT=9999.0),
    pendulum("Blade3", 8.5, 1.3, 1.4, period=4.0, amplitude=2.2, phase=0.0),
    door("ClosingGate3", 10.5, openT=0.0, closeT=9.0),
    block("StepE3", 12.3, 0.6, 1.1, 1.2),
], limit=13)

# ── STAGE 4「大玉と錠前」(制限11/戻し2) 玉が実10に破壊 vs 錠開11 → 玉RW必須 ──
# 錠前がゴールを塞ぐ(開11)のに大玉は実10にゴールへ届く=どう走っても間に合わない。
# 錠前前(実7.5,玉の時計7.5)で玉に-6(実効6)→破壊は実16へ。待って通ってゴール。
build(4, [
    gm(4, 11),
    player(0.8, 2.35, targets="Boulder4,LockGate4",
           arrowStops="Floor4,StartLedge,StepA4,StepB4,StepC4,StepD4",
           solids="Floor4,StartLedge,StepA4,StepB4,StepC4,StepD4,LockGate4", rewindShots=2),
    copy.deepcopy(arrow),
    exit_(15.2, 0.65, "scenes/stage5.json"), gate(15.2, 0.5),
    block("StartLedge", 1.2, 0.9, 2.4, 1.8),
    block("Floor4", 8.0, -0.5, 16.0, 1.0),
    needle("NeedleA4", 5.0, 0.2, 3.6, 0.4),
    block("StepA4", 3.9, 0.6, 1.1, 1.2),
    block("StepB4", 5.6, 0.85, 1.1, 1.7),
    needle("NeedleB4", 10.4, 0.2, 2.6, 0.4),
    block("StepC4", 9.8, 0.6, 1.1, 1.2),
    block("StepD4", 11.2, 0.85, 1.1, 1.7),
    rollball("Boulder4", 2.2, 0.8, 1.6, rollT=0.0, speed=1.3),
    door("LockGate4", 13.5, openT=11.0, closeT=9999.0),
], limit=11)

# ── STAGE 5「時計職人」(制限14/戻し2) 2階の閉門3.0 < 最速3.6 → RW必須 ────────
build(5, [
    gm(5, 14),
    player(0.8, 0.55, targets="Blade5a,GateU,Blade5b,LockGate5",
           arrowStops="Floor5,StairA,StairB,Deck5",
           solids="Floor5,StairA,StairB,Deck5,GateU,LockGate5", rewindShots=2),
    copy.deepcopy(arrow),
    exit_(15.5, 0.65, "scenes/stage6.json"), gate(15.5, 0.5),
    block("Floor5", 8.0, -0.5, 16.0, 1.0),
    pendulum("Blade5a", 4.0, 1.3, 1.4, period=4.0, amplitude=2.2, phase=0.0),
    block("StairA", 5.9, 0.6, 1.2, 1.2),
    block("StairB", 7.1, 1.2, 1.2, 2.4),
    block("Deck5", 10.2, 2.6, 6.0, 0.5),
    door("GateU", 10.0, openT=0.0, closeT=3.0, base=2.85),
    pendulum("Blade5b", 12.0, 4.0, 1.2, period=3.0, amplitude=1.2, phase=1.5),
    door("LockGate5", 14.0, openT=12.0, closeT=9999.0),
], limit=14)

# ── STAGE 6「三重の締切」(制限13/戻し3) 閉門4.0×玉11.5×錠14 → RW2発必須 ──────
build(6, [
    gm(6, 13),
    player(0.8, 2.35, targets="Boulder6,ClosingGate6,LockGate6",
           arrowStops="Floor6,StartLedge6,StepA6,StepB6",
           solids="Floor6,StartLedge6,StepA6,StepB6,ClosingGate6,LockGate6", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(15.5, 0.65, "scenes/stage7.json"), gate(15.5, 0.5),
    block("StartLedge6", 1.2, 0.9, 2.4, 1.8),
    block("Floor6", 8.0, -0.5, 16.0, 1.0),
    needle("Needle6", 5.0, 0.2, 3.6, 0.4),
    block("StepA6", 3.9, 0.6, 1.1, 1.2),
    block("StepB6", 5.6, 0.85, 1.1, 1.7),
    door("ClosingGate6", 9.6, openT=0.0, closeT=4.0),
    rollball("Boulder6", 8.0, 0.8, 1.6, rollT=4.0, speed=1.0),
    door("LockGate6", 13.2, openT=14.0, closeT=9999.0),
], limit=13)

# ── STAGE 7「二階の銀行」(制限15/戻し3) 蛇行+帰路の閉門12(帰着17.5) → RW必須 ──
# 往路: 地上を右へ(閉門x8はまだ開)→右の3段階段→高deck(y4.4)を左へ逆走(刃2枚)→
# 左端の錠前(開16)→飛び降り→帰路のx8はもう閉(12)→呼び戻して潜る。
# 錠前待ち中に刃へ-8の銀行を作らないとタイマーが持たない設計。
build(7, [
    gm(7, 15),
    player(0.8, 0.55, targets="Blade7a,Blade7b,LockGate7,ReturnGate7",
           arrowStops="Floor7,Stair7A,Stair7B,Stair7C,Deck7",
           solids="Floor7,Stair7A,Stair7B,Stair7C,Deck7,LockGate7,ReturnGate7", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(15.5, 0.65, "scenes/stage8.json"), gate(15.5, 0.5),
    block("Floor7", 8.0, -0.5, 16.0, 1.0),
    door("ReturnGate7", 8.0, openT=0.0, closeT=12.0),
    block("Stair7A", 12.2, 0.6, 1.2, 1.2),
    block("Stair7B", 13.4, 1.2, 1.2, 2.4),
    block("Stair7C", 14.6, 1.8, 1.2, 3.6),
    block("Deck7", 8.0, 4.4, 10.0, 0.5),
    pendulum("Blade7a", 10.5, 5.85, 1.4, period=4.0, amplitude=2.0, phase=0.0),
    pendulum("Blade7b", 6.5, 5.85, 1.4, period=4.0, amplitude=2.0, phase=2.0),
    door("LockGate7", 4.5, openT=16.0, closeT=9999.0, base=4.65),
], limit=15)

# ── STAGE 8「卒業試験」(制限18/戻し3) 閉門5.0(RW必須)+錠開26>制限(FF必須) ─────
# 両方の矢を正しい量で使い、さらに刃への銀行(-9=3周期)まで決めて合格。
build(8, [
    gm(8, 18),
    player(0.8, 0.55, targets="Blade8a,GateU8,Blade8b,LockGate8",
           arrowStops="Floor8,Stair8A,Stair8B,Deck8",
           solids="Floor8,Stair8A,Stair8B,Deck8,GateU8,LockGate8", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(15.5, 0.65, "scenes/game_clear.json"), gate(15.5, 0.5),
    block("Floor8", 8.0, -0.5, 16.0, 1.0),
    pendulum("Blade8a", 3.5, 1.3, 1.4, period=4.0, amplitude=2.2, phase=0.0),
    block("Stair8A", 5.3, 0.6, 1.2, 1.2),
    block("Stair8B", 6.5, 1.2, 1.2, 2.4),
    block("Deck8", 9.9, 2.6, 6.0, 0.5),
    door("GateU8", 8.6, openT=0.0, closeT=5.0, base=2.85),
    pendulum("Blade8b", 10.9, 4.0, 1.2, period=3.0, amplitude=1.2, phase=1.5),
    door("LockGate8", 14.0, openT=26.0, closeT=9999.0),
], limit=18)

# 検証: 生成したJSONが読み戻せるか + parent参照がHudCanvasを指すか
for n in range(1, 9):
    s = json.load(open(os.path.join(SCENES, f"stage{n}.json"), encoding="utf-8"))
    names = [e["name"] for e in s["entities"]]
    for e in s["entities"]:
        if "parent" in e:
            assert names[e["parent"]] == "HudCanvas", (n, e["name"])
    assert "DrawAmount" in names and "RewindCount" in names
print("all 8 scenes valid")
