-- title.lua -- タイトル画面。新UIシステム(UICanvas/UIButton/UIAnimator)版。
-- 「動画」のコンセプトをシークバーのモチーフで見せる。STARTボタン/SPACE/ENTERでステージセレクトへ。
local done = false
local demoT = 0
local barFill = nil

function OnStart(self)
  done = false
  demoT = 0
  barFill = scene:findEntity("DemoBarFill")

  events:on("start_clicked", function(e)
    startGame(e and e.source)
  end)
end

function startGame(buttonEntity)
  if done then return end
  done = true
  if buttonEntity then
    scene:tweenUi(buttonEntity, { scale = 0.9, duration = 0.12, easing = "in" })
  end
  goToScene("scenes/stage_select.json", 0.5)
end

function OnUpdate(self, dt)
  demoT = demoT + dt
  if barFill and barFill:isValid() then
    local frac = math.sin(demoT * 0.6) * 0.5 + 0.5
    scene:setUiFill(barFill, frac)
  end

  if not done and (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A") or padPressed("START")) then
    startGame(nil)
  end
end
