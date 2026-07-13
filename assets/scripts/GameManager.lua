-- GameManager.lua -- 「動画」の再生ヘッドそのもの。ステージに1個だけ空エンティティに付ける。
-- 世界時計 t を毎フレーム進め、t >= T(動画の長さ)で TIME UP。プレイヤーの死亡(player_died)も
-- ここで受けて、短い演出の後にシーン再読込(=このステージの動画を最初から再生し直す)。
-- ゴール到達は Exit.lua から "stage_cleared" イベントで受け取り、CLEARリボンを見せてから遷移する。
-- HUD(シークバー/結果リボン)は新UIシステム(UICanvas/UIImage/UIAnimator)側のエンティティを
-- scene:setUiFill/setUiText/setUiColor/showUi で操作する(即時ui:*は使わない)。
properties = {
  { name = "T",         type = "float",  default = 10.0,                     label = "動画の長さ(秒。仕様書により全ステージ共通10.0秒)" },
  { name = "scenePath",  type = "string", default = "scenes/stage1.json",     label = "このシーン自身のパス(リトライ用)" },
  { name = "title",      type = "string", default = "",                      label = "ステージ名(HUD表示、空可)" },
  { name = "markers",    type = "string", default = "",                      label = "シークバーの目印 '秒:ラベル' をカンマ区切りで(現状未使用)" },
}

local seekFill, seekLabel, ribbon, ribbonText

local function showResult(text, r, g, b)
  if not (ribbon and ribbon:isValid()) then return end
  scene:setUiText(ribbonText, text)
  scene:setUiColor(ribbonText, r, g, b, 1.0)
  scene:showUi(ribbon)
end

function OnStart(self)
  self.t = 0
  self.state = "play"   -- play / dead / over / cleared / reloading
  self.waitT = 0
  self.nextScene = nil

  seekFill   = scene:findEntity("SeekBarFill")
  seekLabel  = scene:findEntity("SeekBarLabel")
  ribbon     = scene:findEntity("ResultRibbon")
  ribbonText = scene:findEntity("ResultRibbonText")

  events:on("player_died", function()
    if self.state == "play" then
      self.state = "dead"
      self.waitT = 0.5
      fx:pulse(0.6)
      showResult("MISS...", 0.75, 0.18, 0.15)
    end
  end)

  events:on("stage_goal_ruined", function()
    if self.state == "play" then
      showResult("GOAL DESTROYED...", 0.9, 0.4, 0.3)
    end
  end)

  events:on("stage_cleared", function(data)
    if self.state == "play" then
      self.state = "cleared"
      self.waitT = 1.1
      self.nextScene = (data and data.next) or "scenes/title.json"
      fx:pulse(0.5)
      showResult("STAGE CLEAR!", 0.75, 0.5, 0.05)
    end
  end)
end

local function drawSeekBar(self)
  local frac = clamp(self.t / self.T, 0, 1)
  local remaining = self.T - self.t
  if seekFill and seekFill:isValid() then
    scene:setUiFill(seekFill, frac)
    local low = remaining <= 5
    if low then
      local flash = 0.5 + 0.5 * math.sin(self.t * 14)
      scene:setUiColor(seekFill, 0.95 * flash, 0.3, 0.28, 0.95)
    else
      scene:setUiColor(seekFill, 0.3, 0.75, 0.95, 0.95)
    end
  end
  if seekLabel and seekLabel:isValid() then
    local label = (self.title ~= "" and (self.title .. "  ") or "") .. string.format("%.1f / %.1f s", self.t, self.T)
    scene:setUiText(seekLabel, label)
  end
end

function OnUpdate(self, dt)
  if self.state == "play" then
    self.t = self.t + dt
    if self.t >= self.T then
      self.state = "over"
      self.waitT = 0.7
      fx:pulse(0.7)
      showResult("TIME UP", 0.7, 0.55, 0.1)
    end
    drawSeekBar(self)
  elseif self.state == "dead" or self.state == "over" or self.state == "cleared" then
    self.waitT = self.waitT - dt
    if self.waitT <= 0 then
      if self.state == "cleared" then
        self.state = "reloading"
        goToScene(self.nextScene, 0.5)
      else
        self.state = "reloading"
        goToScene(self.scenePath, 0.3)
      end
    end
  end

  if self.state ~= "reloading" and self.state ~= "cleared" and (keyPressed("R") or padPressed("BACK")) then
    self.state = "reloading"
    goToScene(self.scenePath, 0.2)
  end
end
