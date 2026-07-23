-- OptionsMenu.lua -- 全画面共通のオプションメニュー。OptionsCanvas にアタッチ。
-- ESC / パッドの☰(START) でトグル。mode="play" のシーンではワールドを一時停止し、
-- リトライ/ステージセレクトボタンが付く(押すと "options_retry"/"options_quit" を emit、
-- 受け手は GameManager)。
-- 音量(マスター/BGM/SE)は saveNum(opt_master/opt_bgm/opt_se) で永続化し OnStart で毎シーン適用。
-- 映像設定(画面モード/垂直同期/FPS上限)は display:* が settings.json へ自動永続化+起動時
-- 自動適用するので、ここでは現在値の表示と set 呼び出しだけ行う。
-- スクリプト環境は分離されているので、他スクリプトへの開閉通知はイベント
-- ("options_open"/"options_close")で行う。
properties = {
  { name = "mode", type = "string", default = "menu", label = "menu / play(ポーズ+リトライ付き)" },
}

local canvas
local isOpen = false
local blocked = false   -- play中: GameManager が play 以外(死亡/TIME UP/クリア)の間は開かない
local sfxCd = 0         -- スライダー変更音の連打防止(実時間)

-- 出現アニメを持つ子要素。アニメーターは非表示中でも初回再生が済んでしまうので、
-- 開くたびに showUi で頭から再生し直す(showUi はアニメーターをリセットする)
local ANIMATED = {
  "OptDim", "OptPanel", "OptTitle",
  "OptMasterLabel", "OptMasterSlider", "OptBgmLabel", "OptBgmSlider",
  "OptSeLabel", "OptSeSlider",
  "OptWinModeButton", "OptVsyncToggle", "OptVsyncLabel", "OptFpsButton",
  "OptRetryButton", "OptQuitButton", "OptCloseButton", "OptHint",
}

local WINDOW_MODES = { "windowed", "borderless", "fullscreen" }
local WINDOW_MODE_JP = { windowed = "ウィンドウ", borderless = "ボーダーレス", fullscreen = "フルスクリーン" }
local FPS_PRESETS = { 60, 120, 144, 165, 240, 0 }   -- 0 = 無制限

local function applyVolumes()
  -- 既定値=現在値: ユーザーが一度も触っていなければエンジン/エディタ側の音量を尊重する
  audio:setMasterVolume(loadNum("opt_master", audio:getMasterVolume()))
  audio:setBGMVolume(loadNum("opt_bgm", 1.0))
  audio:setSFXVolume(loadNum("opt_se", 1.0))
end

local function setText(name, text)
  local e = scene:findEntity(name)
  if e and e:isValid() then scene:setUiText(e, text) end
end

local function refreshVideoLabels()
  setText("OptWinModeValue", "画面モード： " .. (WINDOW_MODE_JP[display:getWindowMode()] or "?"))
  local fps = display:getFpsLimit()
  setText("OptFpsValue", "FPS上限： " .. (fps == 0 and "無制限" or tostring(fps)))
end

local function syncWidgets()
  local ms  = scene:findEntity("OptMasterSlider")
  local bgm = scene:findEntity("OptBgmSlider")
  local se  = scene:findEntity("OptSeSlider")
  local vs  = scene:findEntity("OptVsyncToggle")
  if ms  and ms:isValid()  then scene:setUiSlider(ms,  loadNum("opt_master", audio:getMasterVolume())) end
  if bgm and bgm:isValid() then scene:setUiSlider(bgm, loadNum("opt_bgm", 1.0)) end
  if se  and se:isValid()  then scene:setUiSlider(se,  loadNum("opt_se", 1.0))  end
  if vs  and vs:isValid()  then scene:setUiToggle(vs,  display:getVSync()) end
  refreshVideoLabels()
end

local function open(self)
  if isOpen then return end
  isOpen = true
  if self.mode == "play" then
    time.setScale(0)
    physics:setPaused(true)
  end
  syncWidgets()
  scene:showUi(canvas)
  for _, n in ipairs(ANIMATED) do
    local e = scene:findEntity(n)
    if e and e:isValid() then scene:showUi(e) end
  end
  audio:playSFX("audio/ui/menu_select.wav", false)
  events:emit("options_open", {})
  local first = scene:findEntity("OptMasterSlider")
  if first and first:isValid() then setUiFocus(first) end
end

local function close(self)
  if not isOpen then return end
  isOpen = false
  if self.mode == "play" then
    time.setScale(1)
    physics:setPaused(false)
  end
  scene:hideUi(canvas)
  audio:playSFX("audio/ui/menu_select.wav", false)
  events:emit("options_close", {})
end

-- リトライ/セレクトへ: ポーズを解いてから通知(実処理は GameManager が scenePath を知っている)
local function leave(self, eventName)
  if self.mode == "play" then
    time.setScale(1)
    physics:setPaused(false)
  end
  isOpen = false
  scene:hideUi(canvas)
  events:emit(eventName, {})
end

function OnStart(self)
  canvas = scene:findEntity("OptionsCanvas")
  applyVolumes()

  events:on("gm_phase", function(d) blocked = (d.phase ~= "play") end)

  events:on("opt_master_changed", function(e)
    saveNum("opt_master", e.value or 1.0)
    applyVolumes()
  end)
  events:on("opt_bgm_changed", function(e)
    saveNum("opt_bgm", e.value or 1.0)
    applyVolumes()
  end)
  events:on("opt_se_changed", function(e)
    saveNum("opt_se", e.value or 1.0)
    applyVolumes()
    if sfxCd <= 0 then   -- 効果音量の試聴フィードバック
      sfxCd = 0.12
      audio:playSFX("audio/ui/menu_select.wav", false)
    end
  end)

  -- 画面モード: クリックのたびに ウィンドウ → ボーダーレス → フルスクリーン を巡回
  events:on("opt_winmode_clicked", function()
    local cur = display:getWindowMode()
    local idx = 1
    for i, m in ipairs(WINDOW_MODES) do
      if m == cur then idx = i end
    end
    display:setWindowMode(WINDOW_MODES[idx % #WINDOW_MODES + 1])
    refreshVideoLabels()
  end)

  events:on("opt_vsync_changed", function(e)
    display:setVSync((e.value or 0) > 0.5)
    refreshVideoLabels()
  end)

  -- FPS上限: プリセット(60/120/144/165/240/無制限)を巡回。垂直同期ON中はエンジン側で無効
  events:on("opt_fps_clicked", function()
    local cur = display:getFpsLimit()
    local idx = 0
    for i, v in ipairs(FPS_PRESETS) do
      if v == cur then idx = i end
    end
    display:setFpsLimit(FPS_PRESETS[idx % #FPS_PRESETS + 1])
    refreshVideoLabels()
  end)

  events:on("opt_close_clicked", function() close(self) end)
  events:on("opt_retry_clicked", function() leave(self, "options_retry") end)
  events:on("opt_quit_clicked",  function() leave(self, "options_quit")  end)
end

function OnUpdate(self, dt)
  sfxCd = sfxCd - time.realDt()   -- ポーズ中(dt=0)でも減るように実時間
  if keyPressed("ESC") or padPressed("START") then
    if isOpen then
      close(self)
    elseif not (self.mode == "play" and blocked) then
      open(self)
    end
  end
end
