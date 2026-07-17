-- title.lua -- タイトル画面。新UIシステム(UICanvas/UIButton/UIAnimator)版。
-- 「動画」のコンセプトをシークバーのモチーフで見せる。STARTボタン/SPACE/ENTERでステージセレクトへ。
-- BGM(audio/bgm/title.mp3, 128BPM)をループ再生し、経過時間から拍数を計算して
-- Backdrop の effectValue に毎フレーム渡す(TitleBackdrop.hlsl が壁の明滅をビートに同期させる)。
local BGM_PATH   = "audio/bgm/title.mp3"
local BGM_BPM    = 128.0
local BGM_LEAD   = 0.2247    -- デコード先頭から最初の拍まで(mp3エンコーダ由来の無音)
local BGM_LOOP   = 140.8594  -- デコード全長=XAudio2がループする単位(リードイン+300拍)

local UI_SHOW_AT = 0.2247 + 18 * (60.0 / 128.0)   -- ビート18(8.66s)にUIを出す

local done = false
local demoT = 0
local barFill = nil
local bgmT = 0
local wall = nil
local canvas = nil
local uiShown = false
local lastBeat = -1

-- ボタン登場: フェード+ポップ(elastic)+微回転。ラベルは少し遅れてフェード
local function revealButton(btnName, delay)
  local btn = scene:findEntity(btnName)
  if btn and btn:isValid() then
    scene:tweenUi(btn, { alpha = 1, scale = 1.35, rotate = -4,
                         duration = 0.30, easing = "out", delay = delay,
                         onComplete = function()
                           scene:tweenUi(btn, { scale = 1.0, rotate = 0,
                                                duration = 0.55, easing = "elastic" })
                         end })
  end
end

-- 拍バウンス: 音に合わせてちょんと弾む(小節頭は強め)
local function beatBounce(btnName, amp)
  local btn = scene:findEntity(btnName)
  if btn and btn:isValid() then
    scene:tweenUi(btn, { scale = 1 + amp, duration = 0.09, easing = "out",
                         onComplete = function()
                           scene:tweenUi(btn, { scale = 1.0, duration = 0.18, easing = "out" })
                         end })
  end
end

function OnStart(self)
  done = false
  demoT = 0
  barFill = scene:findEntity("DemoBarFill")

  audio:playBGM(BGM_PATH, true)
  bgmT = 0
  wall = scene:findEntity("Backdrop")
  canvas = scene:findEntity("TitleCanvas")
  uiShown = false
  lastBeat = -1
  for _, n in ipairs({ "StartButton", "QuitButton" }) do
    local b = scene:findEntity(n)
    if b and b:isValid() then
      scene:tweenUi(b, { alpha = 0, scale = 0.15, duration = 0.001 })  -- 登場まで透明+極小
    end
  end

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
  if not uiShown and bgmT >= UI_SHOW_AT and canvas and canvas:isValid() then
    uiShown = true
    scene:setUiVisible(canvas, true)
    revealButton("StartButton", 0)
    revealButton("QuitButton", 0.234)   -- 半拍遅れ
  end
  if uiShown and not done then
    local beats = math.floor(math.max(0, (bgmT % BGM_LOOP) - BGM_LEAD) * (BGM_BPM / 60.0))
    if beats ~= lastBeat then
      lastBeat = beats
      local strong = (beats % 4 == 0)
      beatBounce("StartButton", strong and 0.06 or 0.03)
      beatBounce("QuitButton",  strong and 0.05 or 0.025)
    end
  end
  if wall and wall:isValid() then
    local inLoop = bgmT % BGM_LOOP
    local beats = math.max(0, inLoop - BGM_LEAD) * (BGM_BPM / 60.0)
    scene:setMeshEffect(wall, beats)
  end

  if not done and (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A") or padPressed("START")) then
    startGame(nil)
  end
end
