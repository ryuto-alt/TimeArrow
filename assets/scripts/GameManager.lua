-- GameManager.lua -- 「動画」の再生ヘッドそのもの。ステージに1個だけ空エンティティに付ける。
-- 世界時計 t を毎フレーム進め、t >= T(動画の長さ)で TIME UP。プレイヤーの死亡(player_died)も
-- ここで受けて、短い演出の後にシーン再読込(=このステージの動画を最初から再生し直す)。
properties = {
  { name = "T",         type = "float",  default = 10.0,                     label = "動画の長さ(秒。仕様書により全ステージ共通10.0秒)" },
  { name = "scenePath",  type = "string", default = "scenes/stage1.json",     label = "このシーン自身のパス(リトライ用)" },
  { name = "title",      type = "string", default = "",                      label = "ステージ名(HUD表示、空可)" },
  { name = "markers",    type = "string", default = "",                      label = "シークバーの目印 '秒:ラベル' をカンマ区切りで" },
}

local function parseMarkers(csv)
  local out = {}
  for chunk in string.gmatch(csv or "", "[^,]+") do
    local ts, label = chunk:match("^%s*([%d%.]+)%s*:%s*(.-)%s*$")
    if ts then out[#out + 1] = { t = tonumber(ts), label = label } end
  end
  return out
end

function OnStart(self)
  self.t = 0
  self.state = "play"   -- play / dead / over / reloading
  self.waitT = 0
  self.markerList = parseMarkers(self.markers)

  events:on("player_died", function()
    if self.state == "play" then
      self.state = "dead"
      self.waitT = 0.5
      fx:pulse(0.6)
    end
  end)
end

local function drawSeekBar(self)
  local W = SCREEN_W or 1280
  local barW, barH = math.min(720, W - 80), 22
  local barX, barY = (W - barW) * 0.5, 16
  local frac = clamp(self.t / self.T, 0, 1)
  local remaining = self.T - self.t

  ui:rect(barX - 4, barY - 4, barW + 8, barH + 8, 0.05, 0.06, 0.09, 0.75, 8)

  local low = remaining <= 5
  local flash = low and (0.5 + 0.5 * math.sin(self.t * 14)) or 1.0
  ui:rect(barX, barY, barW, barH, 0.16, 0.18, 0.24, 0.9, 5)
  ui:rect(barX, barY, barW * frac, barH,
          low and 0.95 * flash or 0.3, low and 0.3 or 0.75, low and 0.28 or 0.95, 0.95, 5)

  -- 各ギミックのイベント時刻マーカー(このステージの"脚本"が見える)
  for _, m in ipairs(self.markerList) do
    local mf = clamp(m.t / self.T, 0, 1)
    ui:rect(barX + barW * mf - 1, barY - 2, 2, barH + 4, 1, 1, 1, 0.8, 0)
  end

  -- 再生ヘッド(▶)
  local headX = barX + barW * frac
  ui:rect(headX - 2, barY - 8, 4, barH + 16, 1, 0.85, 0.3, 1, 0)

  local label = (self.title ~= "" and (self.title .. "  ") or "") .. string.format("%.1f / %.1f s", self.t, self.T)
  ui:text(barX, barY + barH + 8, label, 20, 1, 1, 1, 1)
end

function OnUpdate(self, dt)
  if _G.gamePaused then return end -- ポーズ中はシークバーもRリトライも止める(PauseMenu.lua)
  if self.state == "play" then
    self.t = self.t + dt
    if self.t >= self.T then
      self.state = "over"
      self.waitT = 0.7
      fx:pulse(0.7)
    end
  elseif self.state == "dead" or self.state == "over" then
    self.waitT = self.waitT - dt
    if self.waitT <= 0 then
      self.state = "reloading"
      goToScene(self.scenePath, 0.3)
    end
  end

  if self.state ~= "reloading" and (keyPressed("R") or padPressed("BACK")) then
    self.state = "reloading"
    goToScene(self.scenePath, 0.2)
  end

  drawSeekBar(self)

  if self.state == "dead" then
    local W = SCREEN_W or 1280
    ui:text(W * 0.5 - 90, 70, "MISS...", 34, 1.0, 0.45, 0.4, 1)
  elseif self.state == "over" then
    local W = SCREEN_W or 1280
    ui:text(W * 0.5 - 110, 70, "TIME UP", 34, 1.0, 0.45, 0.4, 1)
  end
end
