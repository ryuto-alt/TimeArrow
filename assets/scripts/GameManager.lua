-- GameManager.lua -- 「動画」の再生ヘッドそのもの。ステージに1個だけ空エンティティに付ける。
-- 世界時計 t を毎フレーム進め、t >= T(動画の長さ)で TIME UP。プレイヤーの死亡(player_died)も
-- ここで受けて、短い演出の後にシーン再読込(=このステージの動画を最初から再生し直す)。
-- ゴール到達は Exit.lua から "stage_cleared" イベントで受け取り、遷移前に一拍おく。
-- HUDは「YouTube風シークバー(トラック+赤の塗り+画像のつまみ)」+「画面フラッシュ」のみ。
-- 文字は一切出さない(矢を撃った時/失敗した時に画面がごちゃつくのを避けるため)。
-- つまみ(SeekThumb)は setUiPosition 相当のAPIが無いので、scene:tweenUi の dx(相対移動)を
-- 毎フレーム「今回のフレームでの目標X - 前回の目標X」だけ投げて動かす(tweenUiのmoveはUIRect.offsetを
-- 直接書き換える実装なので、後発のtweenは直前のtweenが書いた値を基点に積み上がり、ドリフトしない)。
properties = {
  { name = "T",         type = "float",  default = 10.0,                     label = "動画の長さ(秒。仕様書により全ステージ共通10.0秒)" },
  { name = "scenePath",  type = "string", default = "scenes/stage1.json",     label = "このシーン自身のパス(リトライ用)" },
  { name = "title",      type = "string", default = "",                      label = "ステージ名(現状HUD非表示、記録用)" },
  { name = "markers",    type = "string", default = "",                      label = "シークバーの目印(現状未使用)" },
}

local THUMB_MARGIN = 12.0   -- SeekThumbの半幅(offsetMax.x - offsetMin.x = 24なので半分)
local CANVAS_W = 1280.0

local seekFill, seekThumb, screenFlash
local lastFrac = 0

local function flash(r, g, b, a, fadeDur)
  if not (screenFlash and screenFlash:isValid()) then return end
  scene:setUiColor(screenFlash, r, g, b, a)
  scene:tweenUi(screenFlash, { alpha = 0.0, duration = fadeDur, easing = "out" })
end

function OnStart(self)
  self.t = 0
  self.state = "play"   -- play / dead / over / cleared / reloading
  self.waitT = 0
  self.nextScene = nil

  seekFill    = scene:findEntity("SeekFill")
  seekThumb   = scene:findEntity("SeekThumb")
  screenFlash = scene:findEntity("ScreenFlash")
  lastFrac = 0

  events:on("player_died", function()
    if self.state == "play" then
      self.state = "dead"
      self.waitT = 0.6
      fx:pulse(0.6)
      flash(0.85, 0.12, 0.1, 0.55, 0.7)
    end
  end)

  events:on("stage_goal_ruined", function()
    if self.state == "play" then
      flash(0.55, 0.2, 0.7, 0.4, 0.5)
    end
  end)

  events:on("stage_cleared", function(data)
    if self.state == "play" then
      self.state = "cleared"
      self.waitT = 0.9
      self.nextScene = (data and data.next) or "scenes/title.json"
      fx:pulse(0.5)
      flash(0.4, 0.9, 0.5, 0.45, 0.6)
    end
  end)
end

function OnUpdate(self, dt)
  if self.state == "play" then
    self.t = self.t + dt
    local frac = clamp(self.t / self.T, 0, 1)
    if seekFill and seekFill:isValid() then scene:setUiFill(seekFill, frac) end
    if seekThumb and seekThumb:isValid() and frac ~= lastFrac then
      local span = CANVAS_W - 2.0 * THUMB_MARGIN
      local deltaPx = span * (frac - lastFrac)
      scene:tweenUi(seekThumb, { dx = deltaPx, duration = dt, easing = "linear" })
      lastFrac = frac
    end
    if self.t >= self.T then
      self.state = "over"
      self.waitT = 0.7
      fx:pulse(0.7)
      flash(0.85, 0.55, 0.1, 0.5, 0.7)
    end
  elseif self.state == "dead" or self.state == "over" or self.state == "cleared" then
    self.waitT = self.waitT - dt
    if self.waitT <= 0 then
      self.state = "reloading"
      if self.nextScene then
        goToScene(self.nextScene, 0.5)
      else
        goToScene(self.scenePath, 0.3)
      end
    end
  end

  if self.state ~= "reloading" and self.state ~= "cleared" and (keyPressed("R") or padPressed("BACK")) then
    self.state = "reloading"
    goToScene(self.scenePath, 0.2)
  end
end
