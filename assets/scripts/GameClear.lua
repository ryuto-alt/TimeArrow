-- GameClear.lua -- 全ステージクリア画面。ステージセレクトへ戻るボタンのみ。
local leaving = false

function OnStart(self)
  leaving = false
  events:on("clear_back", function() goBack() end)
end

function goBack()
  if leaving then return end
  leaving = true
  goToScene("scenes/stage_select.json", 0.5)
end

function OnUpdate(self, dt)
  if not leaving and (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A")) then
    goBack()
  end
end
