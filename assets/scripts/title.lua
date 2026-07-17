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
local focusSet = false
local bgmBase = nil    -- 発進時のBGMフェード(元音量はselect側で復元)
local bgmFadeT = 0

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

-- 発進シーケンス(audio/ui/title_warp.wav の波形に同期。立ち上がり0〜0.5s→0.5sクライマックス→1.6sまで残響):
--   0.00s 再生+溜め(title_charge): STARTフラッシュ/QUIT退場/文字が震えてしゃがむ/矢を引き絞る
--   0.50s クライマックス(title_depart): 発射! 矢が飛び出し文字が左から順に追いかける
--   0.70s シークバー早送りワイプ(1.3s)が矢を追って掃く。残響の尻尾に乗せてセレクトが開く
--   BGM は残響に埋もれるよう 0.9s でフェードアウト(音量は select 側 OnStart で復元)
function startGame(buttonEntity)
  if done then return end
  done = true
  audio:playSFX("audio/ui/title_warp.wav", false)
  bgmBase = audio:getBGMVolume()
  saveNum("bgm_restore", bgmBase)
  local sb = scene:findEntity("StartButton")
  local qb = scene:findEntity("QuitButton")
  if sb and sb:isValid() then
    uifx.flash(sb)
    uifx.punch(sb, 1.16, 0.35)
  end
  if qb and qb:isValid() then
    scene:tweenUi(qb, { alpha = 0, dy = 26, duration = 0.3, easing = "in" })
  end
  events:emit("title_charge", {})
  time.after(0.50, function()
    events:emit("title_depart", {})
    fx:pulse(0.6)
    if sb and sb:isValid() then
      scene:tweenUi(sb, { alpha = 0, dx = 70, duration = 0.30, easing = "in" })
    end
  end)
  time.after(0.70, function()
    transitionToScene("scenes/stage_select.json", 4, 1.3)   -- 4=シークバー早送り
  end)
end

function quitGame(buttonEntity)
  if done then return end
  done = true
  for _, n in ipairs({ "StartButton", "QuitButton" }) do
    local b = scene:findEntity(n)
    if b and b:isValid() then
      scene:tweenUi(b, { alpha = 0, scale = 0.8, duration = 0.22, easing = "in" })
    end
  end
  time.after(0.28, function() quit() end)
end

function OnUpdate(self, dt)
  demoT = demoT + dt

  -- 発進後のBGMフェードアウト(warpの残響に隠す)。音量設定は select 側で bgm_restore から復元
  if bgmBase then
    bgmFadeT = bgmFadeT + dt
    local k = 1 - bgmFadeT / 0.9
    if k <= 0 then
      audio:setBGMVolume(0)
      audio:stopBGM()
      bgmBase = nil
    else
      audio:setBGMVolume(bgmBase * k)
    end
  end
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
  if uiShown and not done and not focusSet then
    -- 登場ポップが落ち着いたら START に初期フォーカス(以降は矢印/D-pad/スティックで
    -- START⇄QUIT を移動、Enter/Space/A で決定 = エンジンのフォーカスナビ)
    focusSet = true
    time.after(0.45, function()
      if done then return end
      local sb = scene:findEntity("StartButton")
      if sb and sb:isValid() then setUiFocus(sb) end
    end)
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

  -- UI表示後の Enter/Space/A はエンジンのフォーカスナビが処理する(START⇄QUITを矢印/D-padで
  -- 選んで決定 → start_clicked/quit_clicked が飛んでくる)。ここで直接拾うのはUI表示前の
  -- スキップ入力と、いつでも即スタートのパッドSTARTだけ。
  if not done and (padPressed("START")
      or (not uiShown and (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A")))) then
    startGame(nil)
  end
end
