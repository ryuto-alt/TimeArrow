-- title.lua -- タイトル画面。新UIシステム(UICanvas/UIButton/UIAnimator)版。
-- 「動画」のコンセプトをシークバーのモチーフで見せる。STARTボタン/SPACE/ENTERでステージセレクトへ。
-- BGM(audio/bgm/title.mp3, 128BPM)をループ再生し、経過時間から拍数を計算して
-- Backdrop の effectValue に毎フレーム渡す(TitleBackdrop.hlsl が壁の明滅をビートに同期させる)。
local BGM_PATH   = "audio/bgm/title.mp3"
local BGM_BPM    = 128.0
local BGM_LEAD   = 0.2247    -- デコード先頭から最初の拍まで(mp3エンコーダ由来の無音)
local BGM_LOOP   = 140.8594  -- デコード全長=XAudio2がループする単位(リードイン+300拍)

local done = false
local demoT = 0
local barFill = nil
local bgmT = 0
local wall = nil

function OnStart(self)
  done = false
  demoT = 0
  barFill = scene:findEntity("DemoBarFill")

  audio:playBGM(BGM_PATH, true)
  bgmT = 0
  wall = scene:findEntity("Backdrop")

  events:on("start_clicked", function(e)
    startGame(e and e.source)
  end)

  events:on("quit_clicked", function(e)
    quitGame(e and e.source)
  end)
end

function startGame(buttonEntity)
  if done then return end
  done = true
  if buttonEntity then
    scene:tweenUi(buttonEntity, { scale = 0.9, duration = 0.12, easing = "in" })
  end
  audio:stopBGM()   -- タイトルBGMはタイトル専用
  goToScene("scenes/stage_select.json", 0.5)
end

function quitGame(buttonEntity)
  if done then return end
  done = true
  if buttonEntity then
    scene:tweenUi(buttonEntity, { scale = 0.9, duration = 0.12, easing = "in" })
  end
  quit()
end

function OnUpdate(self, dt)
  demoT = demoT + dt
  if barFill and barFill:isValid() then
    local frac = math.sin(demoT * 0.6) * 0.5 + 0.5
    scene:setUiFill(barFill, frac)
  end

  -- BGMのループ位相から拍数を計算して壁シェーダーへ(ルート定数なので毎フレームでも安価)
  bgmT = bgmT + dt
  if wall and wall:isValid() then
    local inLoop = bgmT % BGM_LOOP
    local beats = math.max(0, inLoop - BGM_LEAD) * (BGM_BPM / 60.0)
    scene:setMeshEffect(wall, beats)
  end

  if not done and (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A") or padPressed("START")) then
    startGame(nil)
  end
end
