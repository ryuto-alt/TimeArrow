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

# ══ 時間経済版レベルデザイン(8ステージ・所要時間シミュレーション済み) ══════════
# 移動5/s・ジャンプ横2.9・針山ホップ区間≈3s・タップ矢+2(0.15s)・フル矢+10(実3s=ゲーム内0.75s)
# 制限時間 = 最適ルート所要 + 約2秒。ペースゲート(開錠待ち)が下限、閉門/大玉が上限を作る。
# 「銀行」テク: 周期Pの振り子に-P×n の後戻り矢 = 位相を変えずタイマーだけ返金(待ち時間を無料化)。

# ── STAGE 1「時は金なり」(制限16秒/まき戻し1) ──────────────────────────
# 橋は10秒かけて自然落下。待つ→着橋10.0/ゴール13.5(余裕2.5)。
# 矢ルート→フル+10で即着橋、ただしタイマーも+10=どちらも同じ頃にゴール(先送り=時間の前借りを体感)。
build(1, [
    gm(1, 16),
    player(1.0, 0.55, targets="Target1", standables="Bridge1",
           arrowStops="FloorL,FloorR", solids="FloorL,FloorR", rewindShots=1),
    copy.deepcopy(arrow),
    exit_(15.0, 0.65, "scenes/stage2.json"), gate(15.0, 0.5),
    block("FloorL", 3.5, -0.5, 7.0, 1.0),
    block("FloorR", 14.0, -0.5, 4.0, 1.0),
    riseplat("Bridge1", 9.5, -0.3, 5.0, 0.6, arriveT=0.0, trigger="Target1",
             waitHeight=6.0, riseTime=10.0),
    target("Target1", 6.0, 4.5, 1.1),
], limit=16)

# ── STAGE 2「二枚の閉門」(制限13秒/まき戻し3) ─────────────────────────
# 門A=6秒/門B=9秒で閉まる。全力(針山3s)ならA5.8→B8.5→ゴール10.2(生身クリア可・余裕2.8)。
# 遅れたら後戻り矢で門の時計を戻す(実際に戻せた分だけタイマー返金)。
build(2, [
    gm(2, 13),
    player(1.0, 0.55, targets="GateA,GateB",
           arrowStops="Floor2,StepA,StepB",
           solids="Floor2,StepA,StepB,GateA,GateB", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(15.0, 0.65, "scenes/stage3.json"), gate(15.0, 0.5),
    block("Floor2", 8.0, -0.5, 16.0, 1.0),
    needle("Needle2", 4.8, 0.2, 3.6, 0.4),
    block("StepA", 3.7, 0.6, 1.1, 1.2),
    block("StepB", 5.4, 0.85, 1.1, 1.7),
    door("GateA", 8.0, openT=0.0, closeT=6.0),
    door("GateB", 12.0, openT=0.0, closeT=9.0),
], limit=13)

# ── STAGE 3「振り子銀行」(制限19秒/まき戻し2) ─────────────────────────
# 刃(周期4)2.5s→リフト(到着時は頂上=+3で最下段を呼ぶ)→2階デッキ→刃→降りて時限錠17秒。
# 素直ルート: 錠前到着≈11→開錠17→ゴール17.4(余裕1.6でギリ)。
# 銀行ルート: 錠前待ちの間に刃へ-8(2周期=位相不変)→タイマー8秒返金で余裕9.6。
build(3, [
    gm(3, 19),
    player(0.8, 0.55, targets="Blade3,Lift3,Blade3b,LockGate3", standables="Lift3",
           arrowStops="Floor3,Deck3", solids="Floor3,Deck3,LockGate3", rewindShots=2),
    copy.deepcopy(arrow),
    exit_(15.4, 0.65, "scenes/stage4.json"), gate(15.4, 0.5),
    block("Floor3", 8.0, -0.5, 16.0, 1.0),
    pendulum("Blade3", 4.0, 1.3, 1.4, period=4.0, amplitude=2.2, phase=0.0),
    moveplat("Lift3", 7.5, 2.45, 2.2, 0.5, period=6.0, amplitude=1.95, phase=4.5),
    block("Deck3", 10.75, 4.4, 4.5, 0.5),
    pendulum("Blade3b", 10.75, 5.75, 1.4, period=4.0, amplitude=1.8, phase=1.0),
    door("LockGate3", 14.0, openT=17.0, closeT=9999.0),
], limit=19)

# ── STAGE 4「大玉レース」(制限15秒/まき戻し3) ─────────────────────────
# 大玉がt=2から1.2/sで追走、12.5秒にゴール破壊。針山2区間の全力走で所要9.5(余裕3)。
# 転んだら: 後戻り矢-6で破壊を18.5秒へ(返金付き)。先送り+10で玉をゴールの向こうへ捨てるのは
# タイマー+10=制限15秒ではほぼ自殺(=やりすぎのデメリットを体で学ぶ)。
build(4, [
    gm(4, 15),
    player(0.8, 2.35, targets="Boulder4",
           arrowStops="Floor4,StartLedge,StepA4,StepB4,StepC4,StepD4",
           solids="Floor4,StartLedge,StepA4,StepB4,StepC4,StepD4", rewindShots=3),
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
    rollball("Boulder4", 2.6, 0.8, 1.6, rollT=2.0, speed=1.2),
], limit=15)

# ── STAGE 5「時計職人」(制限19秒/まき戻し2) 2階建て ────────────────────
# 刃2.5s→階段→2階の閉門(8秒。急げば5.5で通過/遅れたら-Xで呼び戻し)→短周期刃(3秒)→
# 降りて時限錠15秒→ゴール16.8(余裕2.2)。閉門を呼び戻した場合は返金があるので実は楽になる。
build(5, [
    gm(5, 19),
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
    door("GateU", 10.0, openT=0.0, closeT=8.0, base=2.85),
    pendulum("Blade5b", 12.0, 4.0, 1.2, period=3.0, amplitude=1.2, phase=1.5),
    door("LockGate5", 14.0, openT=15.0, closeT=9999.0),
], limit=19)

# ── STAGE 6「三重の締切」(制限18秒/まき戻し3) ─────────────────────────
# 締切サンド: 閉門7秒(急げ)×大玉11.5秒にゴール破壊(遅らせろ)×時限錠14秒(待て)。
# 大玉は先送りで捨てると+8でタイマー即死(=後戻り-6で延命が唯一の正解筋)。
# 想定: 針山を6.3秒で抜け閉門通過→玉に-6(破壊17.5へ+返金)→錠前14→ゴール15.7(余裕2.3)。
build(6, [
    gm(6, 18),
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
    door("ClosingGate6", 9.6, openT=0.0, closeT=7.0),
    rollball("Boulder6", 8.0, 0.8, 1.6, rollT=4.0, speed=1.0),
    door("LockGate6", 13.2, openT=14.0, closeT=9999.0),
], limit=18)

# ── STAGE 7「二階の銀行」(制限24秒/まき戻し3) 蛇行ルート ─────────────────
# 地上を右へ→右端の階段で2階へ→デッキを左へ逆走(刃2枚・位相2秒ずれ)→左端の時限錠20秒→
# 飛び降りてデッキの下を右へ全力→ゴール。素直: 23.2(余裕0.8のカミソリ)。
# 錠前待ち中に刃2枚へ-8×2の銀行=タイマー16秒返金で快適(まき戻し3発の使いどころ)。
build(7, [
    gm(7, 24),
    player(0.8, 0.55, targets="Blade7a,Blade7b,LockGate7",
           arrowStops="Floor7,Stair7A,Stair7B,Deck7",
           solids="Floor7,Stair7A,Stair7B,Deck7,LockGate7", rewindShots=3),
    copy.deepcopy(arrow),
    exit_(15.5, 0.65, "scenes/stage8.json"), gate(15.5, 0.5),
    block("Floor7", 8.0, -0.5, 16.0, 1.0),
    block("Stair7A", 13.4, 0.6, 1.2, 1.2),
    block("Stair7B", 14.6, 1.2, 1.2, 2.4),
    block("Deck7", 8.0, 2.6, 10.0, 0.5),
    pendulum("Blade7a", 11.0, 4.0, 1.4, period=4.0, amplitude=2.0, phase=0.0),
    pendulum("Blade7b", 7.0, 4.0, 1.4, period=4.0, amplitude=2.0, phase=2.0),
    door("LockGate7", 4.5, openT=20.0, closeT=9999.0, base=2.85),
], limit=24)

# ── STAGE 8「卒業試験」(制限25秒/まき戻し3) 全要素 ───────────────────────
# 刃(周期4)→階段→2階の閉門10秒→短周期刃(周期3)→降りて時限錠22秒→ゴール23.3(余裕1.7)。
# 合格筋: どこかで最低1回の銀行(-6〜-8)を作らないと事故1回で終わる。
# 逆に先送りの浪費(+10癖)はそのまま敗因になる。時間の家計簿の卒業試験。
build(8, [
    gm(8, 25),
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
    door("GateU8", 8.6, openT=0.0, closeT=10.0, base=2.85),
    pendulum("Blade8b", 10.9, 4.0, 1.2, period=3.0, amplitude=1.2, phase=1.5),
    door("LockGate8", 14.0, openT=22.0, closeT=9999.0),
], limit=25)

# 検証: 生成したJSONが読み戻せるか + parent参照がHudCanvasを指すか
for n in range(1, 9):
    s = json.load(open(os.path.join(SCENES, f"stage{n}.json"), encoding="utf-8"))
    names = [e["name"] for e in s["entities"]]
    for e in s["entities"]:
        if "parent" in e:
            assert names[e["parent"]] == "HudCanvas", (n, e["name"])
    assert "DrawAmount" in names and "RewindCount" in names
print("all 8 scenes valid")
