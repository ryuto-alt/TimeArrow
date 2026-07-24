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
  -- 開発者コマンド: F3=タイトルへ即帰還(プレイ会の進行用)
  local f3 = false
  pcall(function() f3 = input:isKeyPressed(KEY_F3) end)
  if f3 and not leaving then
    leaving = true
    audio:stopBGM()
    goToScene("scenes/title.json", 0.3)
    return
  end
  if not leaving and not optionsOpen
     and (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A")) then
    goBack()
  end
end
