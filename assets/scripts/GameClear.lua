-- GameClear.lua -- 全ステージクリア画面。クリアBGMを流し、ステージセレクトへ戻る。
-- 背景の祝祭演出は GameClearBackdrop.hlsl(ClearBackdrop エンティティ)が担当。
local leaving = false
local optionsOpen = false

function OnStart(self)
  leaving = false
  audio:playBGM("audio/bgm/game_clear.mp3", true)
  events:on("clear_back", function() goBack() end)

  local canvas = scene:findEntity("ClearCanvas")
  events:on("options_open", function()
    optionsOpen = true
    if canvas and canvas:isValid() then scene:hideUi(canvas) end
  end)
  events:on("options_close", function()
    optionsOpen = false
    if canvas and canvas:isValid() and not leaving then scene:showUi(canvas) end
  end)
end

function goBack()
  if leaving then return end
  leaving = true
  goToScene("scenes/stage_select.json", 0.5)
end

function OnUpdate(self, dt)
  if not leaving and not optionsOpen
     and (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A")) then
    goBack()
  end
end
