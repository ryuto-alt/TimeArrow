-- GameManager.lua -- 「動画」の再生ヘッドそのもの。ステージに1個だけ空エンティティに付ける。
-- 世界時計 t を毎フレーム進め、t >= T(動画の長さ)で TIME UP。プレイヤーの死亡(player_died)も
-- ここで受けて、短い演出の後にシーン再読込(=このステージの動画を最初から再生し直す)。
-- ゴール到達は Exit.lua から "stage_cleared" イベントで受け取り、遷移前に一拍おく。
-- HUD: シークバー + 画面フラッシュ + テキスト2種(DotGothic16フォント):
--   TimeBanner「◯秒以内にゴールしろ！」(開始2.4秒で消える) / TimeLeft 残り秒数(3秒切ると赤)。
properties = {
  { name = "T",         type = "float",  default = 10.0,                     label = "動画の長さ(秒。仕様書により全ステージ共通10.0秒)" },
  { name = "scenePath",  type = "string", default = "scenes/stage1.json",     label = "このシーン自身のパス(リトライ用)" },
  { name = "title",      type = "string", default = "",                      label = "ステージ名(現状HUD非表示、記録用)" },
  { name = "markers",    type = "string", default = "",                      label = "シークバーの目印(現状未使用)" },
}

local seekBar, screenFlash, timeBanner, timeLeft

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
  self.rewindGlow = 0

  seekBar     = scene:findEntity("SeekBar")
  screenFlash = scene:findEntity("ScreenFlash")
  timeBanner  = scene:findEntity("TimeBanner")
  timeLeft    = scene:findEntity("TimeLeft")
  self.bannerT = 2.4
  self.lastShown = -1
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)

  -- 時間経済: 先送り矢=刺した量だけ制限時間も消費 / 後戻り矢=刺した量だけ返金。
  -- シークバーが跳ねる/戻るので、コストと利得が目に見える
  events:on("time_skip", function(data)
    if self.state ~= "play" then return end
    self.t = self.t + (data.amount or 0)
  end)
  events:on("time_rewind", function(data)
    if self.state ~= "play" then return end
    self.rewindGlow = 0.25
  end)
  -- 返金は「対象が実際に巻き戻せた量」だけ(ギミック側が消化しながら発行する)
  events:on("time_refund", function(data)
    if self.state ~= "play" then return end
    self.t = math.max(0, self.t - (data.amount or 0))
  end)

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
  -- 後戻り中は画面全体を薄い紫に(時間が逆流している合図)。止めた瞬間フェードアウト
  if self.rewindGlow > 0 then
    self.rewindGlow = self.rewindGlow - dt
    if screenFlash and screenFlash:isValid() then
      if self.rewindGlow > 0 then
        scene:setUiColor(screenFlash, 0.5, 0.35, 1.0, 0.12)
      else
        scene:tweenUi(screenFlash, { alpha = 0.0, duration = 0.25, easing = "out" })
      end
    end
  end

  -- 開始バナーは少し見せたらフェードアウト
  if self.bannerT > 0 then
    self.bannerT = self.bannerT - dt
    if self.bannerT <= 0 and timeBanner and timeBanner:isValid() then
      scene:tweenUi(timeBanner, { alpha = 0.0, duration = 0.4, easing = "out" })
    end
  end

  if self.state == "play" then
    self.t = self.t + dt * self.ts
    if seekBar and seekBar:isValid() then scene:setUiSlider(seekBar, self.t) end

    -- 残り秒数(0.1秒刻みで更新。ラスト3秒は赤に切り替え)
    if timeLeft and timeLeft:isValid() then
      local remain = math.max(0, self.T - self.t)
      local shown = math.floor(remain * 10)
      if shown ~= self.lastShown then
        self.lastShown = shown
        scene:setUiText(timeLeft, string.format("%.1f", remain))
        if remain < 3 and not self.redOn then
          self.redOn = true
          pcall(function() scene:setUiColor(timeLeft, 1.0, 0.25, 0.2, 1.0) end)
        end
      end
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
