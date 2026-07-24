-- StageIntro.lua -- ステージ開幕シネマ(IntroDirector に付ける)。
-- 「◯◯秒以内にゴールしろ！」を3Dモデル(真鍮ボード+DotGothic押し出し文字、Blender自作)で
-- カメラ正面に展開 → 数字が上から落下スラム → 溜め → 全部吹き飛んで「スタート！」が
-- 奥からズーム参上 → 世界が動き出す。演出中は events "stage_intro"{on=true} と
-- "time_scale"{scale=0} で世界を凍結する(Player/GameManager/全ギミックが従う)。
-- リトライ(死亡/R)では ta_retry_* フラグ(GameManager が立てる)を読んで短縮版になる。
-- SPACE/E/Q/ENTER/パッドA でスキップ可。
properties = {
  { name = "limit",    type = "float",  default = 10.0, label = "制限時間(数字表示用)" },
  { name = "retryKey", type = "string", default = "",   label = "リトライ短縮フラグの永続キー" },
}

-- カメラ規約(CameraFollow.lua と同じ pitch 14度)
local FWD_Y, FWD_Z = -0.2419, 0.9703   -- forward = (0, -sin14, cos14)
local UP_Y,  UP_Z  =  0.9703, 0.2419   -- up      = (0,  cos14, sin14)
local DIST = 11.0                       -- カメラからの距離(この奥行きの画面半高≈5.1)

local T_PLATE  = 0.10   -- ボード回転参上
local T_DIGIT  = 0.55   -- 数字スラム開始(1文字ごと+0.16)
local T_OUT    = 2.35   -- 全員吹き飛び
local T_START  = 2.60   -- スタート!参上
local T_GO     = 2.80   -- 世界が動き出す(スタート!はまだ画面に残る)
local T_END    = 3.70   -- 完全撤収

local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function easeOutCubic(u) local v = 1 - u; return 1 - v * v * v end
local function easeInQuad(u) return u * u end
local function easeOutBack(u)
  local c1, c3 = 1.70158, 2.70158
  local v = u - 1
  return 1 + c3 * v * v * v + c1 * v * v
end

function OnStart(self)
  self.t = 0
  self.started = false
  self.done = false
  self.goFired = false
  self.cam = scene:findEntity("GameCamera")
  self.flash = scene:findEntity("ScreenFlash")
  self.plate = scene:findEntity("IntroPlate")
  self.start = scene:findEntity("IntroStart")
  self.startOut = scene:findEntity("IntroStartOut")
  self.digits = {}
  self.digitOuts = {}
  for i = 1, 3 do
    local e = scene:findEntity("IntroDigit" .. i)
    if e and e:isValid() then
      self.digits[#self.digits + 1] = e
      -- タイトル(TitleCharOut)方式の2段構造: 太らせた暗色縁取りを背後に重ねる
      self.digitOuts[#self.digits] = scene:findEntity("IntroDigit" .. i .. "Out")
    end
  end
  -- リトライなら短縮版(スタート!だけ)。フラグは読んだら消す
  self.quick = false
  if self.retryKey ~= "" then
    if loadPersist(self.retryKey, 0) == 1 then self.quick = true end
    savePersist(self.retryKey, 0)
  end
  if self.quick then self.t = T_OUT + 0.1 end

  -- ボード幅(モデル実寸8.9)とスケールからレイアウトを決める
  self.plateS = 0.60
  self.digitS = 1.15
  local plateW = 8.9 * self.plateS
  local n = #self.digits
  local numW = n * 0.95 * self.digitS
  local total = numW + 0.25 + plateW
  self.numLeft = -total / 2            -- グループ左端(数字から始まる)
  self.plateX  = -total / 2 + numW + 0.25 + plateW / 2
  self.groupY  = 1.35                  -- 画面中央より少し上
end

-- カメラ基準のオフセット(ox=右, oy=上)→ワールド座標
local function place(self, e, ox, oy, rz, s, extraD)
  local c = self.cam.transform.position
  local d = DIST + (extraD or 0)
  local wx = c.x + ox
  local wy = c.y + FWD_Y * d + UP_Y * oy
  local wz = c.z + FWD_Z * d + UP_Z * oy
  e.transform.position = Vec3.new(wx, wy, wz)
  e.transform.rotation = Vec3.new(0, 0, rz or 0)
  e.transform.scale = Vec3.new(s, s, s)
end

-- 本体+縁取りをセットで配置。縁取りは0.35奥に置くが、カメラから見て同一視線上・
-- 同一見かけサイズになるよう位置とスケールを距離比で補正する(輪郭が全方向均等に出る)
local function placePair(self, e, out, ox, oy, rz, s, extraD)
  place(self, e, ox, oy, rz, s, extraD)
  if out and out:isValid() then
    local d0 = DIST + (extraD or 0)
    local k = (d0 + 0.35) / d0
    place(self, out, ox * k, oy * k, rz, s * k, (extraD or 0) + 0.35)
  end
end

local function hide(e)
  if e and e:isValid() then e.transform.position = Vec3.new(0, -200, 0) end
end

local function worldOf(self, ox, oy)
  local c = self.cam.transform.position
  return c.x + ox, c.y + FWD_Y * DIST + UP_Y * oy, c.z + FWD_Z * DIST + UP_Z * oy
end

function OnUpdate(self, dt)
  if self.done then return end
  if not (self.cam and self.cam:isValid()) then return end

  -- 初回フレームで凍結(全エンティティの OnStart 完了後に発行するためここで)
  if not self.started then
    self.started = true
    events:emit("stage_intro", { on = true })
    events:emit("time_scale", { scale = 0 })
    self.glow = 0       -- モデルのフラッシュ発光(IntroGlow.hlsl の effectValue へ)
    self.blip = 0       -- 画面の白ブリップ(スラム時に一瞬明るく)
  end

  self.t = self.t + dt
  local t = self.t

  -- ── 画面オーバーレイ: 薄暗転(モデルは自発光シェーダーで沈まない)+スラム白ブリップ ──
  self.blip = math.max(0, (self.blip or 0) - dt * 3.5)
  if not self.goFired and self.flash and self.flash:isValid() then
    local b = self.blip
    scene:setUiColor(self.flash,
                     0.02 + 0.98 * b, 0.04 + 0.92 * b, 0.10 + 0.75 * b,
                     0.30 + 0.25 * b)
  end

  -- ── モデルの発光を減衰させながら毎フレーム配る ──
  self.glow = math.max(0, (self.glow or 0) - dt * 4.0)
  local function feed(e)
    if e and e:isValid() then scene:setMeshEffect(e, self.glow) end
  end
  feed(self.plate)
  feed(self.start)
  for _, e in ipairs(self.digits) do feed(e) end

  -- スキップ(吹き飛びフェーズへ早送り)
  if t < T_OUT and (keyPressed("SPACE") or keyPressed("E") or keyPressed("Q")
                    or keyPressed("ENTER") or padPressed("A")) then
    self.t = T_OUT
    t = T_OUT
  end

  -- ── ボード: 左からスピン参上 → 溜めの震え ──────────────────
  if self.plate and self.plate:isValid() and not self.quick then
    if t < T_PLATE then
      hide(self.plate)
    elseif t < T_OUT then
      local u = easeOutCubic(clamp01((t - T_PLATE) / 0.40))
      local ox = -26 + (self.plateX + 26) * u
      local rz = 380 * (1 - u)
      local pop = 0.8 + 0.2 * easeOutBack(clamp01((t - T_PLATE) / 0.45))
      -- 溜め: 数字が全部落ちたあと小刻みに震える
      local riser = clamp01((t - 1.2) / (T_OUT - 1.2))
      local tr = (math.sin(t * 43) + math.sin(t * 61)) * 0.02 * riser
      place(self, self.plate, ox + tr, self.groupY + tr * 0.7, rz, self.plateS * pop)
      -- 参上中は金の光跡を撒き散らす+着地の瞬間に衝撃波
      if u < 1 then
        local wx, wy, wz = worldOf(self, ox, self.groupY)
        FX.trail(wx - 1.5, wy, wz - 0.5, 1.0, 0.85, 0.4)
        FX.trail(wx + 1.5, wy + 0.3, wz - 0.5, 1.0, 0.7, 0.3)
      elseif not self.plateSlam then
        self.plateSlam = true
        self.glow = 1.2
        self.blip = 0.5
        local wx, wy, wz = worldOf(self, self.plateX, self.groupY)
        FX.shockwave(wx, wy, wz - 0.5, 14, 8, 1.0, 0.85, 0.4)
        FX.spark(wx, wy, wz - 0.5, 20, 1.0, 0.85, 0.4)
        fx:pulse(0.25)
      end
    else
      -- 吹き飛び: 右上へ加速しつつスピン(金の残光を引く)
      local u = t - T_OUT
      local ox = self.plateX + 40 * u * u
      place(self, self.plate, ox, self.groupY + 6 * u * u, -50 * u, self.plateS)
      if u < 0.5 then
        local wx, wy, wz = worldOf(self, ox, self.groupY + 6 * u * u)
        FX.trail(wx, wy, wz - 0.5, 1.0, 0.8, 0.35)
      end
      if t > T_OUT + 0.6 then hide(self.plate) end
    end
  end

  -- ── 数字: 上から順に落下スラム(着地で衝撃波) ────────────────
  if not self.quick then
    for i, e in ipairs(self.digits) do
      if e and e:isValid() then
        local out = self.digitOuts[i]
        local ox = self.numLeft + (i - 0.5) * 0.95 * self.digitS
        local t0 = T_DIGIT + (i - 1) * 0.16
        if t < t0 then
          hide(e)
          hide(out)
        elseif t < T_OUT then
          local u = clamp01((t - t0) / 0.22)
          local oy = self.groupY + 7.0 * (1 - easeInQuad(u))
          -- 着地の瞬間: 二重衝撃波+火花大量+白ブリップ+落雷ビーム
          if u >= 1 and not self["slam" .. i] then
            self["slam" .. i] = true
            self.glow = 1.8
            self.blip = 0.8
            local wx, wy, wz = worldOf(self, ox, self.groupY)
            FX.shockwave(wx, wy - 0.4, wz - 0.5, 12, 8, 1.0, 0.8, 0.3)
            FX.shockwave(wx, wy - 0.4, wz - 0.5, 20, 5, 1.0, 0.95, 0.7)
            FX.spark(wx, wy - 0.5, wz - 0.5, 30, 1.0, 0.85, 0.35)
            -- 落下軌道の残光(上から突き刺さった感)
            FX.beam(wx, wy + 6.0, wz - 0.5, wx, wy - 0.3, wz - 0.5,
                    1.0, 0.9, 0.5, 0.22, "energy", 5)
            fx:burst{ x = wx, y = wy - 0.5, z = wz - 0.5, kind = "star", count = 6,
                      size = 0.4, sizeEnd = 0.05, life = 0.7, speed = 5, spread = 1.0,
                      gravity = -6, r = 1.0, g = 0.85, b = 0.4 }
            fx:pulse(0.35)
            padVibrate(0.5, 0.5, 0.12)
            audio:playSFX("audio/se/arrow_hit.wav", false)
          end
          -- 着地後: 心拍のように脈打つ(緊張感)
          local s = self.digitS
          if u >= 1 then
            local beat = math.exp(-((t - t0) % 0.62) * 5)
            s = s * (1 + 0.10 * beat)
          else
            s = s * (1.6 - 0.6 * u)   -- 落下中は大きく→等倍(奥から迫る感)
          end
          placePair(self, e, out, ox, oy, 0, s)
        else
          -- 吹き飛び: 数字は四方へ散る
          local u = t - T_OUT
          local dir = (i % 2 == 0) and 1 or -1
          placePair(self, e, out, ox + dir * 25 * u * u, self.groupY + (14 - i * 6) * u * u,
                    dir * 240 * u, self.digitS)
          if t > T_OUT + 0.6 then
            hide(e)
            hide(out)
          end
        end
      end
    end
    -- 溜め中: 火花の二重周回(時間の輪)+金の噴水+周期パルスリング
    if t > 1.2 and t < T_OUT then
      local cx = self.numLeft + (#self.digits * 0.95 * self.digitS) / 2
      for k = 0, 1 do
        local a = -t * 7.0 + k * math.pi
        local wx, wy, wz = worldOf(self, cx + math.cos(a) * 1.9, self.groupY + math.sin(a) * 1.9)
        FX.trail(wx, wy, wz - 0.5, 1.0, 0.85, 0.4)
      end
      -- 群全体の足元から金の火花が噴き上がる
      self.fountainT = (self.fountainT or 0) + dt
      if self.fountainT > 0.07 then
        self.fountainT = 0
        local fx0 = self.numLeft + math.random() * (self.plateX + 2.8 - self.numLeft)
        local wx, wy, wz = worldOf(self, fx0, self.groupY - 1.4)
        fx:burst{ x = wx, y = wy, z = wz - 0.5, kind = "spark", count = 3,
                  size = 0.22, sizeEnd = 0, life = 0.8, speed = 3.5, spread = 0.4,
                  gravity = 2.5, dy = 1, r = 1.0, g = 0.8, b = 0.35 }
      end
      -- 鼓動に合わせて背後にパルスリング
      self.ringT = (self.ringT or 0) + dt
      if self.ringT > 0.62 then
        self.ringT = 0
        local wx, wy, wz = worldOf(self, cx, self.groupY)
        FX.shockwave(wx, wy, wz + 0.5, 16, 4, 1.0, 0.75, 0.3)
        self.glow = math.max(self.glow, 0.5)
      end
    end
  end

  -- ── スタート!: 奥からズーム参上 → 着弾フラッシュ ─────────────
  if self.start and self.start:isValid() then
    if t < T_START then
      hide(self.start)
      hide(self.startOut)
    elseif t < T_END then
      local u = clamp01((t - T_START) / 0.20)
      local pop = easeOutBack(u)
      local s = 1.05 * pop
      local extraD = 14 * (1 - easeOutCubic(u))   -- 奥(遠く)から手前へ
      if u >= 1 and not self.startSlam then
        self.startSlam = true
        self.glow = 2.2
        local wx, wy, wz = worldOf(self, 0, 0.3)
        -- 三重衝撃波+星型8方向ビーム+火花大量=最大の見せ場
        FX.shockwave(wx, wy, wz - 0.5, 18, 10, 0.45, 0.9, 1.0)
        FX.shockwave(wx, wy, wz - 0.5, 30, 6, 1.0, 0.95, 0.7)
        FX.shockwave(wx, wy, wz + 0.5, 44, 4, 0.6, 0.85, 1.0)
        for k = 0, 7 do
          local a = k * math.pi / 4
          FX.beam(wx, wy, wz - 0.5,
                  wx + math.cos(a) * 5.5, wy + math.sin(a) * 5.5, wz - 0.5,
                  1.0, 0.9, 0.55, 0.28, "energy", 6)
        end
        FX.spark(wx, wy, wz - 0.5, 40, 1.0, 0.9, 0.5)
        fx:burst{ x = wx, y = wy, z = wz - 0.5, kind = "star", count = 14,
                  size = 0.5, sizeEnd = 0.06, life = 0.9, speed = 8, spread = 1.0,
                  gravity = -5, r = 0.6, g = 0.9, b = 1.0 }
        fx:pulse(0.8)
        padVibrate(0.8, 0.8, 0.22)
        audio:playSFX("audio/se/start.wav", false)
        if self.flash and self.flash:isValid() then
          scene:setUiColor(self.flash, 0.9, 0.98, 1.0, 0.7)
          scene:tweenUi(self.flash, { alpha = 0.0, duration = 0.5, easing = "out" })
        end
      end
      if t < T_GO + 0.35 then
        local tr = (self.startSlam and t < T_START + 0.5)
                   and (math.sin(t * 70) * 0.03 * (1 - u)) or 0
        placePair(self, self.start, self.startOut, tr, 0.3, 0, math.max(s, 0.0001), extraD)
      else
        -- 役目を終えて上へ飛び去る
        local v = clamp01((t - T_GO - 0.35) / 0.5)
        placePair(self, self.start, self.startOut, 0, 0.3 + 7 * easeInQuad(v), 8 * v,
                  1.05 * (1 - 0.7 * v))
      end
    end
  end

  -- ── 世界の再始動 ───────────────────────────────────────────
  if t >= T_GO and not self.goFired then
    self.goFired = true
    events:emit("time_scale", { scale = 1 })
    events:emit("stage_intro", { on = false })
    if self.flash and self.flash:isValid() then
      scene:tweenUi(self.flash, { alpha = 0.0, duration = 0.3, easing = "out" })
    end
  end

  if t >= T_END then
    self.done = true
    hide(self.plate)
    hide(self.start)
    hide(self.startOut)
    for _, e in ipairs(self.digits) do hide(e) end
    for _, e in pairs(self.digitOuts) do hide(e) end
  end
end