-- GameManager.lua -- 「動画」の再生ヘッドそのもの。ステージに1個だけ空エンティティに付ける。
-- 世界時計 t を毎フレーム進め、t >= T(動画の長さ)で TIME UP。プレイヤーの死亡(player_died)も
-- ここで受けて、短い演出の後にシーン再読込(=このステージの動画を最初から再生し直す)。
-- ゴール到達は Exit.lua から "stage_cleared" イベントで受け取り、遷移前に一拍おく。
-- HUDは「YouTube風シークバー(UISlider、操作不可の表示専用。トラック+赤の塗り+丸つまみを
-- エンジンが自前描画)」+「画面フラッシュ」のみ。文字は一切出さない
-- (矢を撃った時/失敗した時に画面がごちゃつくのを避けるため)。
properties = {
  { name = "T",         type = "float",  default = 10.0,                     label = "動画の長さ(秒。仕様書により全ステージ共通10.0秒)" },
  { name = "scenePath",  type = "string", default = "scenes/stage1.json",     label = "このシーン自身のパス(リトライ用)" },
  { name = "title",      type = "string", default = "",                      label = "ステージ名(現状HUD非表示、記録用)" },
  { name = "markers",    type = "string", default = "",                      label = "シークバーの目印(現状未使用)" },
}

local seekBar, screenFlash

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

  seekBar     = scene:findEntity("SeekBar")
  screenFlash = scene:findEntity("ScreenFlash")

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
    if seekBar and seekBar:isValid() then scene:setUiSlider(seekBar, self.t) end
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
