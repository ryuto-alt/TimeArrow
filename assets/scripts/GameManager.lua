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

-- リトライでの再読込前に印を残す → StageIntro.lua が読んで開幕シネマを短縮版にする
local function markRetry(self)
  local stem = self.scenePath and self.scenePath:match("([%w_]+)%.json")
  if stem then savePersist("ta_retry_" .. stem, 1) end
end

local function flash(r, g, b, a, fadeDur)
  if not (screenFlash and screenFlash:isValid()) then return end
  scene:setUiColor(screenFlash, r, g, b, a)
  scene:tweenUi(screenFlash, { alpha = 0.0, duration = fadeDur, easing = "out" })
end

function OnStart(self)
  self.t = 0
  -- IntroDirector(StageIntro.lua)がいるステージは開幕シネマが終わるまで "intro" で待機
  self.state = "play"   -- intro / play / dead / over / cleared / reloading
  local dir = scene:findEntity("IntroDirector")
  if dir and dir:isValid() then self.state = "intro" end
  events:on("stage_intro", function(d)
    if self.state == "intro" and not (d and d.on) then self.state = "play" end
  end)
  self.waitT = 0
  self.nextScene = nil
  self.rewindGlow = 0
  time.setScale(1)      -- TIME UP演出のsetScale(0)をリロード後に持ち越さない保険

  seekBar     = scene:findEntity("SeekBar")
  screenFlash = scene:findEntity("ScreenFlash")
  timeBanner  = scene:findEntity("TimeBanner")
  timeLeft    = scene:findEntity("TimeLeft")

  -- ステージBGM: 内容に随伴(2026-07-24のstage2⇔4入替を反映)。
  -- 時計台ダンジョン=工房(stage2)と風の谷(stage3) / 最終回廊(stage4)=専用曲 /
  -- 時計仕掛け=それ以外
  local stageNo = tonumber(tostring(self.scenePath):match("stage(%d+)")) or 1
  local clocktower = (stageNo == 2 or stageNo == 3)
  local bgm = (stageNo == 4 and "audio/bgm/stage_final.mp3")
              or (clocktower and "audio/bgm/stage_clocktower.mp3")
              or "audio/bgm/stage_clockwork.mp3"
  audio:playBGM(bgm, true)
  -- 後戻り用: 同じ曲の逆再生早送りスニペット(areverse+1.7x事前生成)
  self.bgmRev = (stageNo == 4 and "audio/se/bgm_rev_final.wav")
                or (clocktower and "audio/se/bgm_rev_clocktower.wav")
                or "audio/se/bgm_rev_clockwork.wav"
  self.bannerT = 2.4
  self.lastShown = -1
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)

  -- 時間経済: 先送り矢=刺した量だけ制限時間も消費 / 後戻り矢=刺した量だけ返金。
  -- シークバーが跳ねる/戻るので、コストと利得が目に見える
  -- 先送りの代償は半額。等額だと「先送り=その場で待つ」と数学的に等価になり、
  -- 矢の存在意義が消える(実時間の締切だけを出し抜ける、割引された時間の前借り)
  events:on("time_skip", function(data)
    if self.state ~= "play" then return end
    self.t = self.t + (data.amount or 0) * 0.5
    -- 先送り中: ステージBGM自体を早送り(消化テンポ1.5sぶん2倍速)
    pcall(function() audio:setBGMRate(2.0) end)
    self.ffRateT = 1.6
  end)
  -- 後戻りの返金: 撃った瞬間に量×0.35を即時返金(2026-07-24ユーザー指示)。
  -- 旧仕様の「対象が実際に巻き戻せた量×0.5をじわじわ返金」は、対象の時計が浅いと
  -- ほとんど戻らず「戻りが少なすぎる」ため廃止。先送り(×0.5)より30%少ない固定率にして
  -- 予測可能に。FF→RW往復は 0.5-0.35=0.15 の目減り=時間の錬金術も引き続き不成立
  events:on("time_rewind", function(data)
    if self.state ~= "play" then return end
    self.t = math.max(0, self.t - (data.amount or 0) * 0.35)
    self.rewindGlow = 0.25
    -- 後戻り中: BGMを止めて同じ曲の逆再生早送りを重ねる(=曲が巻き戻る)
    audio:pauseBGM()
    audio:playSFX(self.bgmRev, false)
    self.rwMuteT = 1.7
  end)

  -- オプションメニュー(OptionsMenu.lua)連携: 開いている間は入力を止め、
  -- play 以外の局面(死亡/TIME UP/クリア演出中)は開かせない(gm_phase で通知)
  self.optionsOpen = false
  events:on("options_open",  function() self.optionsOpen = true  end)
  events:on("options_close", function() self.optionsOpen = false end)
  events:on("options_retry", function()
    if self.state == "reloading" then return end
    self.state = "reloading"
    time.setScale(1)
    markRetry(self)
    goToScene(self.scenePath, 0.2)
  end)
  events:on("options_quit", function()
    if self.state == "reloading" then return end
    self.state = "reloading"
    time.setScale(1)
    audio:stopBGM()
    goToScene("scenes/stage_select.json", 0.4)
  end)

  events:on("player_died", function()
    if self.state == "play" then
      self.state = "dead"
      events:emit("gm_phase", { phase = "dead" })
      self.waitT = 0.6
      fx:pulse(0.6)
      flash(0.85, 0.12, 0.1, 0.55, 0.7)
      audio:playSFX("audio/se/miss.wav", false)
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
      events:emit("gm_phase", { phase = "cleared" })
      self.waitT = 0.9
      self.nextScene = (data and data.next) or "scenes/title.json"
      fx:pulse(0.5)
      flash(0.4, 0.9, 0.5, 0.45, 0.6)
      audio:playSFX("audio/se/stage_clear.wav", false)
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

  -- 先送りのBGM早送りを戻す
  if self.ffRateT then
    self.ffRateT = self.ffRateT - dt
    if self.ffRateT <= 0 then
      self.ffRateT = nil
      pcall(function() audio:setBGMRate(1.0) end)
    end
  end
  -- 後戻りの逆再生が終わったらBGM復帰
  if self.rwMuteT then
    self.rwMuteT = self.rwMuteT - dt
    if self.rwMuteT <= 0 then
      self.rwMuteT = nil
      if self.state == "play" then audio:resumeBGM() end
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
      -- TIME UP: 時が割れる。ガラス音(timeup_glass.wav)は頭0秒がインパクトなので
      -- 鳴らした瞬間に世界を止めて(setScale 0)、破片が飛び散り→暗転→リロード。
      self.state = "over"
      events:emit("gm_phase", { phase = "over" })
      self.waitT = 2.2
      self.overT = 0
      time.setScale(0)
      audio:stopBGM()
      audio:stopAllSFX()   -- 逆再生スニペット等が鳴っていたら止めてガラスに集中
      audio:playSFX("audio/se/timeup_glass.wav", false)
      fx:pulse(1.0)
      local cx, cy, cz = 0, 0, 0
      local pl = scene:findEntity("Player")
      if pl and pl:isValid() then
        local pp = pl.transform.position
        cx, cy, cz = pp.x, pp.y, pp.z
      end
      self.shX, self.shY, self.shZ = cx, cy, cz
      if screenFlash and screenFlash:isValid() then
        scene:setUiColor(screenFlash, 1, 1, 1, 0.9)   -- 割れた瞬間の白閃光(減衰は下で手動)
      end
      -- 画面いっぱいにガラス片が弾け飛ぶ(パーティクルはsetScale対象外なので止まらない)
      for i = 1, 14 do
        local ox, oy = (math.random() - 0.5) * 16, (math.random() - 0.5) * 9
        fx:burst{ x = cx + ox, y = cy + oy, z = cz, kind = "star", count = 6,
                  size = 0.5, sizeEnd = 0.08, life = 1.1, speed = 6, spread = 1.0,
                  gravity = -9, r = 0.72, g = 0.9, b = 1.0 }
        fx:burst{ x = cx + ox, y = cy + oy, z = cz, kind = "spark", count = 10,
                  size = 0.26, sizeEnd = 0, life = 0.9, speed = 8, spread = 1.0,
                  gravity = -13, r = 0.55, g = 0.8, b = 1.0 }
      end
      FX.shockwave(cx, cy, cz, 30, 20, 0.8, 0.95, 1.0)
    end
  elseif self.state == "dead" or self.state == "over" or self.state == "cleared" then
    -- over中は setScale(0) で dt=0 なので実時間で進める
    local step = (self.state == "over") and time.realDt() or dt
    self.waitT = self.waitT - step

    if self.state == "over" then
      self.overT = self.overT + step
      -- 破片の降りしきり(最初の0.8秒)
      self.shardAcc = (self.shardAcc or 0) + step
      if self.overT < 0.8 and self.shardAcc > 0.1 then
        self.shardAcc = 0
        fx:burst{ x = self.shX + (math.random() - 0.5) * 14,
                  y = self.shY + 3.5 + math.random() * 3, z = self.shZ,
                  kind = "spark", count = 6, size = 0.22, sizeEnd = 0, life = 0.8,
                  speed = 3, spread = 0.6, gravity = -14, dy = -1,
                  r = 0.6, g = 0.85, b = 1.0 }
      end
      -- 白閃光の減衰 → 暗転(手動制御。tweenのタイムスケール依存を避ける)
      if screenFlash and screenFlash:isValid() then
        if self.overT < 0.5 then
          scene:setUiColor(screenFlash, 1, 1, 1, 0.9 * (1 - self.overT / 0.5))
        elseif self.overT > 0.9 then
          scene:setUiColor(screenFlash, 0, 0, 0, math.min(1, (self.overT - 0.9) / 0.6))
        end
      end
    end

    if self.waitT <= 0 then
      self.state = "reloading"
      time.setScale(1)
      if self.nextScene then
        goToScene(self.nextScene, 0.5)
      else
        markRetry(self)
        goToScene(self.scenePath, 0.3)
      end
    end
  end

  if self.state ~= "reloading" and self.state ~= "cleared" and not self.optionsOpen
     and (keyPressed("R") or padPressed("Y")) then
    self.state = "reloading"
    time.setScale(1)
    markRetry(self)
    goToScene(self.scenePath, 0.2)
  end

  -- 開発者コマンド: F3=タイトルへ即帰還(プレイ会の進行用。ポーズ中でも効く)
  local f3 = false
  pcall(function() f3 = input:isKeyPressed(KEY_F3) end)
  if f3 and self.state ~= "reloading" then
    self.state = "reloading"
    time.setScale(1)
    audio:stopBGM()
    goToScene("scenes/title.json", 0.3)
  end
end
