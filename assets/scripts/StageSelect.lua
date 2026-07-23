-- StageSelect.lua -- ステージセレクト画面。選択中のカードが縮んで消え、次のカードが逆側から
-- 拡がって出てくるカルーセル演出(仕様書のステージセレクトスケッチを再現)。
local STAGES = {
  { path = "scenes/stage0.json", name = "TUTORIAL" },
  { path = "scenes/stage1.json", name = "STAGE 1" },
  { path = "scenes/stage2.json", name = "STAGE 2" },
  { path = "scenes/stage3.json", name = "STAGE 3" },
  { path = "scenes/stage4.json", name = "STAGE 4" },
}
local SLIDE = 160.0
local OUT_DUR = 0.16
local SNAP_DUR = 0.001
local IN_DUR = 0.26

local index = 1
local panel, cardTitle, cardNumber
local state = "idle"   -- idle / out / in
local timer = 0
local dir = 1
local leaving = false
local entryT = 0       -- 入場演出中の入力猶予タイマー

local function group()
  return { panel, cardTitle, cardNumber }
end

local function updateLabels()
  local st = STAGES[index]
  scene:setUiText(cardTitle, st.name)
  scene:setUiText(cardNumber, index .. " / " .. #STAGES)
end

-- 入場振付: シークワイプが開くのに合わせて要素をずらして登場させる
local ENTER_AT = 0.45            -- ワイプ(1.3s)の開きに合わせた登場開始タイミング
local function prep(name, p)
  local e = scene:findEntity(name)
  if e and e:isValid() then
    p.duration = 0.001
    p.alpha = 0
    scene:tweenUi(e, p)
    return e
  end
end
local function enter(e, delay, p)
  if not e then return end
  p.alpha = 1
  p.duration = p.duration or 0.40
  p.delay = delay
  p.easing = p.easing or "out"
  scene:tweenUi(e, p)
end

function OnStart(self)
  -- タイトルの発進でフェードアウトした BGM 音量設定を復元(BGM自体は止まっている)
  audio:setBGMVolume(loadNum("bgm_restore", audio:getBGMVolume()))

  panel      = scene:findEntity("StageCardPanel")
  cardTitle  = scene:findEntity("StageCardTitle")
  cardNumber = scene:findEntity("StageCardNumber")
  index = 1
  updateLabels()

  -- 入場: title_warp の残響(〜1.6s)に乗せてゆったりフェードイン。
  -- ヘッダー→カード→送りボタン→下段の順で、クリックから約4秒で全員着席する
  enter(prep("SelectHeader", { dy = -46 }), ENTER_AT, { dy = 0, duration = 0.7 })
  for _, e in ipairs(group()) do
    if e and e:isValid() then
      scene:tweenUi(e, { alpha = 0, scale = 0.82, duration = 0.001 })
      scene:tweenUi(e, { alpha = 1, scale = 1, duration = 0.8, delay = ENTER_AT + 0.20, easing = "back" })
    end
  end
  enter(prep("PrevButton", { dx = -56 }), ENTER_AT + 0.45, { dx = 0, duration = 0.7 })
  enter(prep("NextButton", { dx = 56 }),  ENTER_AT + 0.45, { dx = 0, duration = 0.7 })
  enter(prep("PlayButton", { dy = 42 }),  ENTER_AT + 0.60, { dy = 0, duration = 0.7 })
  enter(prep("BackButton", { dy = 42 }),  ENTER_AT + 0.75, { dy = 0, duration = 0.7 })

  events:on("stage_prev", function() beginTransition(-1) end)
  events:on("stage_next", function() beginTransition(1) end)
  events:on("stage_play", function() goPlay() end)
  events:on("stage_back", function() goBack() end)
end

function beginTransition(direction)
  if state ~= "idle" or leaving then return end
  audio:playSFX("audio/ui/menu_select.wav", false)
  dir = direction
  state = "out"
  timer = 0
  for _, e in ipairs(group()) do
    if e and e:isValid() then
      scene:tweenUi(e, { dx = dir * -SLIDE, alpha = 0.0, duration = OUT_DUR, easing = "in" })
    end
  end
end

function goPlay()
  if leaving then return end
  leaving = true
  -- 決定音+カードをパンチしてからシークバー早送りワイプでステージへ(タイトル→セレクトと同じ言語)
  audio:playSFX("audio/ui/menu_enter.wav", false)
  if panel and panel:isValid() then uifx.punch(panel, 1.10, 0.25) end
  local path = STAGES[index].path
  time.after(0.22, function()
    transitionToScene(path, 4, 0.9)
  end)
end

function goBack()
  if leaving then return end
  leaving = true
  audio:playSFX("audio/ui/menu_select.wav", false)
  goToScene("scenes/title.json", 0.4)
end

function OnUpdate(self, dt)
  if leaving then return end
  entryT = entryT + dt

  if state == "out" then
    timer = timer + dt
    if timer >= OUT_DUR then
      index = index + dir
      if index > #STAGES then index = 1 end
      if index < 1 then index = #STAGES end
      updateLabels()
      for _, e in ipairs(group()) do
        if e and e:isValid() then
          scene:tweenUi(e, { dx = dir * (2 * SLIDE), alpha = 0.0, duration = SNAP_DUR })
        end
      end
      state = "in"
      timer = 0
    end
  elseif state == "in" then
    timer = timer + dt
    if timer >= SNAP_DUR + 0.02 then
      for _, e in ipairs(group()) do
        if e and e:isValid() then
          scene:tweenUi(e, { dx = dir * -SLIDE, alpha = 1.0, duration = IN_DUR, easing = "out" })
        end
      end
      state = "idle"
    end
  end

  if not leaving and state == "idle" and entryT > 1.6 then
    if keyPressed("LEFT") or keyPressed("A") or padPressed("DPAD_LEFT") then beginTransition(-1) end
    if keyPressed("RIGHT") or keyPressed("D") or padPressed("DPAD_RIGHT") then beginTransition(1) end
    if keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A") then goPlay() end
    if keyPressed("ESC") or padPressed("B") then goBack() end
  end
end
