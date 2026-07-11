-- PauseMenu.lua -- ESC / パッドSTARTで開くポーズメニュー。MenuCanvas に付ける。
-- 一時停止 = time.setScale(0) + physics:setPaused(true) + _G.gamePaused(各スクリプトの入力/描画ゲート)
properties = {}

local function applyAudio(self)
  audio:setBGMVolume(self.bgm)
  audio:setSFXVolume(self.se)
  audio:setMasterVolume(self.mute and 0 or 1)
end

local function setPaused(self, on)
  self.open = on
  _G.gamePaused = on
  time.setScale(on and 0 or 1)
  physics:setPaused(on)
  if on then
    scene:setUiVisible(self.canvas, true)
    scene:showUi(self.canvas) -- 出現アニメをリプレイ
    self.optOpen = false
    scene:setUiVisible(self.panel, false)
  else
    scene:setUiVisible(self.canvas, false)
  end
end

function OnStart(self)
  self.canvas = scene:findEntity("MenuCanvas")
  self.panel  = scene:findEntity("OptionsPanel")
  self.open = false
  self.optOpen = false

  -- ポーズ中のリトライ(R)でスケール0/ポーズが次のシーンに持ち越されるのを防ぐ
  _G.gamePaused = false
  time.setScale(1)
  physics:setPaused(false)
  scene:setUiVisible(self.canvas, false)

  -- 設定の復元(saveNum/loadNum で永続化)
  self.bgm  = loadNum("opt_bgm", 0.8)
  self.se   = loadNum("opt_se", 0.8)
  self.mute = loadNum("opt_mute", 0) > 0.5
  applyAudio(self)
  scene:setUiSlider(scene:findEntity("BgmSlider"), self.bgm)
  scene:setUiSlider(scene:findEntity("SeSlider"), self.se)
  scene:setUiToggle(scene:findEntity("FsToggle"), self.mute)

  events:on("ui_resume", function() setPaused(self, false) end)

  events:on("ui_options", function()
    self.optOpen = not self.optOpen
    if self.optOpen then
      scene:setUiVisible(self.panel, true)
      scene:showUi(self.panel)
    else
      scene:setUiVisible(self.panel, false)
    end
  end)

  events:on("ui_quit", function()
    setPaused(self, false)
    goToScene("scenes/title.json", 0.5)
  end)

  events:on("ui_bgm", function(e)
    self.bgm = e.value
    saveNum("opt_bgm", self.bgm)
    applyAudio(self)
  end)

  events:on("ui_se", function(e)
    self.se = e.value
    saveNum("opt_se", self.se)
    applyAudio(self)
  end)

  events:on("ui_mute", function(e)
    self.mute = e.value > 0.5
    saveNum("opt_mute", self.mute and 1 or 0)
    applyAudio(self)
  end)
end

function OnUpdate(self, dt)
  if keyPressed("ESC") or padPressed("START") then
    setPaused(self, not self.open)
  end
end
