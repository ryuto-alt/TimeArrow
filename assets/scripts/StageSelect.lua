-- StageSelect.lua -- ステージセレクト画面。選択中のカードが縮んで消え、次のカードが逆側から
-- 拡がって出てくるカルーセル演出(仕様書のステージセレクトスケッチを再現)。
local STAGES = {
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

local function group()
  return { panel, cardTitle, cardNumber }
end

local function updateLabels()
  local st = STAGES[index]
  scene:setUiText(cardTitle, st.name)
  scene:setUiText(cardNumber, index .. " / " .. #STAGES)
end

function OnStart(self)
  panel      = scene:findEntity("StageCardPanel")
  cardTitle  = scene:findEntity("StageCardTitle")
  cardNumber = scene:findEntity("StageCardNumber")
  index = 1
  updateLabels()

  events:on("stage_prev", function() beginTransition(-1) end)
  events:on("stage_next", function() beginTransition(1) end)
  events:on("stage_play", function() goPlay() end)
  events:on("stage_back", function() goBack() end)
end

function beginTransition(direction)
  if state ~= "idle" or leaving then return end
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
  goToScene(STAGES[index].path, 0.5)
end

function goBack()
  if leaving then return end
  leaving = true
  goToScene("scenes/title.json", 0.4)
end

function OnUpdate(self, dt)
  if leaving then return end

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

  if not leaving and state == "idle" then
    if keyPressed("LEFT") or keyPressed("A") or padPressed("DPAD_LEFT") then beginTransition(-1) end
    if keyPressed("RIGHT") or keyPressed("D") or padPressed("DPAD_RIGHT") then beginTransition(1) end
    if keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A") then goPlay() end
    if keyPressed("ESC") or padPressed("B") then goBack() end
  end
end
