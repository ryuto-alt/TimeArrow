-- TitleLogoIntro.lua -- タイトル演出ディレクター(BGM title.mp3 / 128BPM に完全同期)。
-- 構成(拍グリッド t=0.2247+k*0.46875、拍16=7.72sがサビ頭):
--   拍0-8   タイムストリーム: 文字が高速で右→左へ流れ続ける(時間の巻き戻し)
--   拍8-12  集結: 流れが反転し、文字が弧を描いて左→右へ自席に「未点灯」で着地
--   拍12-16 溜め: ライザーに同期して全文字が震え、拍14で弓がスピン参上→矢をドロー
--   拍16    サビ: 発射!矢先が通過した文字から順に点灯して跳ねる「ぽん!」
--   以降    拍に合わせたダンス。カメラは全編ゆっくり前進、着弾でシェイク。
-- 各エンティティのJSON上のtransformが「最終ポーズ」の基準値。
properties = {
  { name = "danceAmp", type = "float", default = 1.0, min = 0, max = 3, label = "ダンスの強さ" },
}

-- 曲同期定数(title.lua と一致させること)
local BPM  = 128.0
local SPB  = 60.0 / BPM
local LEAD = 0.2247
local LOOP = 140.8594
local function beatAt(k) return LEAD + k * SPB end

local T_GATHER = beatAt(8)     -- 3.975 集結開始
local T_DRAW   = beatAt(12)    -- 5.850 溜め(キック抜け)
local T_BOW    = beatAt(14)    -- 6.787 弓スピン参上
local T_NOCK   = beatAt(14.6)  -- 7.068 矢つがえ
local T_DROP   = beatAt(16)    -- 7.725 サビ/発射
local FLIGHT   = 0.20
local T_IMPACT = T_DROP + FLIGHT

local CHAR_N   = 9
local NOCK_SX  = 0.32
local DIM      = { 0.30, 0.40, 0.52 }   -- 未点灯カラー

local STREAM_SPEED = 55                  -- ストリーム速度(m/s)
local STREAM_DUR   = 50 / STREAM_SPEED   -- 1本の滞空時間
local LANES = { 2.1, 3.3, 4.7, 5.5 }

local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function easeOutCubic(u) local v = 1 - u; return 1 - v * v * v end
local function easeInQuad(u) return u * u end
local function easeOutBack(u)
  local c1, c3 = 1.70158, 2.70158
  local v = u - 1
  return 1 + c3 * v * v * v + c1 * v * v
end

local function brightColor(i)
  local u = (i - 1) / 8.0
  return 0.50 + 0.32 * u, 0.88 + 0.08 * u, 1.0
end

function OnStart(self)
  self.clock = 0
  self.chars = {}
  for i = 1, CHAR_N do
    local e = scene:findEntity("TitleChar" .. i)
    if e and e:isValid() then
      local t = e.transform
      self.chars[i] = { ent = e, px = t.position.x, py = t.position.y, pz = t.position.z,
                        s = t.scale.x, lit = false }
      scene:setColor(e, DIM[1], DIM[2], DIM[3])   -- 未点灯で開始(サビで点灯)
    end
  end
  local function grab(name)
    local e = scene:findEntity(name)
    if e and e:isValid() then
      local t = e.transform
      return { ent = e, px = t.position.x, py = t.position.y, pz = t.position.z,
               sx = t.scale.x, sy = t.scale.y, sz = t.scale.z }
    end
    return nil
  end
  self.arrow = grab("TitleArrow")
  self.bow   = grab("TitleBow")
  self.cam   = grab("GameCamera")
  self.wall  = scene:findEntity("Backdrop")
end

-- ストリーム(拍0-8): 半拍ごとに1文字が右→左へ横切る。gcd(4,9)=1 なので全文字が巡る
local function streamEvent(self, i, t)
  for k = 0, 30 do
    if (k * 4 + 1) % 9 + 1 == i then
      local t0 = beatAt(k * 0.25)
      local u = (t - t0) / STREAM_DUR
      if u >= 0 and u < 1 then
        return {
          x = 25 - STREAM_SPEED * (t - t0),
          y = LANES[k % 4 + 1],
          stretch = 1.55 - 0.35 * math.sin(u * math.pi),  -- スピード変形
        }
      end
    end
  end
  return nil
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  local t = self.clock
  local beats = math.max(0, (t % LOOP) - LEAD) / SPB
  local beatPulse = math.exp(-(beats % 1) * 5)
  local barPulse  = math.exp(-((beats * 0.25) % 1) * 8)
  local riser = clamp01((t - T_DRAW) / (T_DROP - T_DRAW))   -- 溜めの進行(0..1)

  -- ── カメラ: 全編ゆっくり前進、着弾でシェイク ─────────────
  if self.cam then
    local c = self.cam
    local z = c.pz - 1.3 + 1.3 * easeInQuad(clamp01(t / T_DROP))
    local sx, sy = 0, 0
    local sh = (t - T_IMPACT) / 0.20
    if sh >= 0 and sh < 1 then
      local a = (1 - sh) * 0.07
      sx = math.sin(t * 87) * a
      sy = math.cos(t * 73) * a
    end
    c.ent.transform.position = Vec3.new(c.px + sx, c.py + sy, z)
  end

  -- ── 壁: サビまで点滅ゼロ→発射で解禁+画面フラッシュ「ぴか!」 ──
  if self.wall and self.wall:isValid() then
    local inten, flash = 0.0, 0.0
    if t >= T_DROP then
      inten = 1.0 + 0.4 * math.exp(-(t - T_DROP) * 6)
      flash = 0.9 * math.exp(-(t - T_DROP) * 5.5)
      if flash < 0.005 then flash = 0 end
    end
    scene:setMeshParams(self.wall, inten, flash, 0, 0)
  end

  -- ── 弓: 拍14でスピン参上→ドロー→発射反動→バク転退場 ──────
  if self.bow then
    local b = self.bow
    if t < T_BOW then
      b.ent.transform.scale = Vec3.new(0.0001, 0.0001, 0.0001)
    else
      local x, y, rz = b.px, b.py, 0
      local sx, sy, sz = b.sx, b.sy, b.sz
      if t < T_BOW + 0.35 then
        local u = easeOutCubic(clamp01((t - T_BOW) / 0.35))
        x = -26 + (b.px + 26) * u
        rz = 540 * (1 - u)
        local pop = easeOutBack(u)
        sx, sy, sz = b.sx * pop, b.sy * pop, b.sz * pop
      elseif t < T_DROP then
        local tremble = (math.sin(t * 31) + math.sin(t * 47)) * 0.014 * riser
        x = b.px + tremble
        y = b.py + tremble * 0.7
        rz = -4 * riser
        sx = b.sx * (1 - 0.07 * easeInQuad(riser))
      elseif t < T_IMPACT + 0.15 then
        local u = clamp01((t - T_DROP) / 0.25)
        x = b.px - 0.35 * (1 - easeOutCubic(u))
        rz = 8 * (1 - easeOutCubic(u))
      else
        local u = clamp01((t - T_IMPACT - 0.15) / 0.55)
        if u >= 1 then
          b.ent.transform.scale = Vec3.new(0.0001, 0.0001, 0.0001)
        else
          local v = easeInQuad(u)
          x = b.px - 10 * v
          y = b.py + 3 * v
          rz = -360 * v   -- バク転しながら退場
        end
      end
      if t < T_IMPACT + 0.70 then
        b.ent.transform.position = Vec3.new(x, y, b.pz)
        b.ent.transform.rotation = Vec3.new(0, 0, rz)
        b.ent.transform.scale    = Vec3.new(sx, sy, sz)
      end
      scene:setMeshEffect(b.ent, beats)
      scene:setMeshParams(b.ent, 0.15 + 0.85 * riser, 0, 0, 0)
    end
  end

  -- ── 矢 ─────────────────────────────────────────────
  local tipX = -999   -- 矢先の現在位置(文字の点灯トリガー)
  if self.arrow then
    local a = self.arrow
    scene:setMeshEffect(a.ent, beats)
    scene:setMeshParams(a.ent, (t < T_DROP) and 0.15 or 1.0, 0, 0, 0)
    local bowX = self.bow and self.bow.px or -17.0
    local halfNock = 7.8 * a.sx * NOCK_SX
    if t < T_NOCK then
      a.ent.transform.scale = Vec3.new(0.0001, 0.0001, 0.0001)
    elseif t < T_DROP then
      local appear = easeOutBack(clamp01((t - T_NOCK) / 0.12))
      local draw = 0.8 * easeInQuad(clamp01((t - T_NOCK) / (T_DROP - T_NOCK)))
      local tremble = (math.sin(t * 37) + math.sin(t * 53)) * 0.010 * riser
      a.ent.transform.position = Vec3.new(bowX + halfNock - 0.55 - draw, a.py + tremble, a.pz)
      a.ent.transform.rotation = Vec3.new(0, 0, 0)
      a.ent.transform.scale    = Vec3.new(a.sx * NOCK_SX * appear, a.sy * 0.7 * appear, a.sz * 0.7 * appear)
    elseif t < T_IMPACT then
      -- 飛翔: 伸びながら本来のアンダーラインへ
      local u = clamp01((t - T_DROP) / FLIGHT)
      local startX = bowX + halfNock - 1.35
      local x = startX + (a.px - startX) * u
      local grow = NOCK_SX + (1.12 - NOCK_SX) * easeOutCubic(u)
      tipX = x + 7.8 * a.sx * grow
      a.ent.transform.position = Vec3.new(x, a.py, a.pz)
      a.ent.transform.rotation = Vec3.new(0, 0, -3 * (1 - u))
      a.ent.transform.scale    = Vec3.new(a.sx * grow, a.sy * (0.7 + 0.3 * u), a.sz * (0.7 + 0.3 * u))
    else
      tipX = 999
      local u = clamp01((t - T_IMPACT) / 0.18)
      local sx = a.sx * (1.12 - 0.12 * easeOutCubic(u))
      local y, rz = a.py, 0
      if t >= T_IMPACT + 0.3 then
        y = y + beatPulse * 0.05 * self.danceAmp
        rz = math.sin(beats * math.pi) * 0.8 * self.danceAmp
      end
      a.ent.transform.position = Vec3.new(a.px, y, a.pz)
      a.ent.transform.rotation = Vec3.new(0, 0, rz)
      a.ent.transform.scale    = Vec3.new(sx, a.sy, a.sz)
    end
  end

  -- ── 文字 ────────────────────────────────────────────
  for i, c in pairs(self.chars) do
    local x, y, rz = c.px, c.py, 0
    local sxm, sym = 1, 1     -- スケール倍率(基準 c.s に乗算)
    local gatherAt = T_GATHER + (i - 1) * 0.35 * SPB
    local gatherU  = clamp01((t - gatherAt) / (1.4 * SPB))

    if t < gatherAt then
      -- タイムストリーム: 右→左へ横切る(担当イベントが無ければ画面外)
      local ev = streamEvent(self, i, t)
      if ev then
        x, y = ev.x, ev.y
        sxm, sym = ev.stretch, 1 / ev.stretch
      else
        sxm, sym = 0.0001, 0.0001
      end
    elseif gatherU < 1 then
      -- 集結: 左から弧を描いて自席へ(未点灯のまま)
      local u = easeOutCubic(gatherU)
      x = -30 + (c.px + 30) * u
      y = c.py + math.sin(gatherU * math.pi) * 1.6 * ((i % 2 == 0) and 1 or -1) * 0.6
      rz = -30 * (1 - u)
      local pop = 0.85 + 0.15 * easeOutBack(gatherU)
      sxm, sym = pop, pop
      -- 着地スクワッシュ
      if gatherU > 0.85 then
        local w = math.sin(clamp01((gatherU - 0.85) / 0.15) * math.pi)
        sym = sym * (1 - 0.18 * w)
      end
    else
      -- 着席済み。溜めの震え → 矢先が通過したら点灯して「ぽん!」
      if not c.lit then
        local tremble = (math.sin(t * 35 + i * 1.7) + math.sin(t * 51 + i)) * 0.028 * riser
        x = c.px + tremble
        y = c.py + tremble * 0.8
        rz = -2.5 * riser
        if tipX >= c.px or t >= T_IMPACT then
          c.lit = true
          c.litAt = t
          local r, g, bl = brightColor(i)
          scene:setColor(c.ent, r, g, bl)
        end
      end
      if c.lit then
        local pu = clamp01((t - c.litAt) / 0.28)
        local kick = 1 - easeOutCubic(pu)
        y = c.py + kick * 0.45
        rz = ((i % 2 == 0) and 1 or -1) * kick * 7
        local pop = 1 + 0.22 * kick
        sxm, sym = pop, pop
        -- 点灯後はダンス(位相は左から右へ波)
        if pu >= 1 then
          local phase = (beats - (i - 1) * 0.06) % 1
          local bounce = math.exp(-phase * 5)
          local alt = (i % 2 == 0) and 1 or -1
          y = y + (bounce * 0.10 + barPulse * 0.07) * self.danceAmp
          rz = rz + (math.sin(beats * math.pi + i * 0.55) * 1.6 + alt * barPulse * 2.2) * self.danceAmp
          local ds = 1 + (0.05 * bounce + 0.035 * barPulse) * self.danceAmp
          sxm, sym = sxm * ds, sym * ds
        end
      end
    end

    c.ent.transform.position = Vec3.new(x, y, c.pz)
    c.ent.transform.rotation = Vec3.new(0, 0, rz)
    c.ent.transform.scale    = Vec3.new(c.s * sxm, c.s * sym, c.s * sxm)
    scene:setMeshEffect(c.ent, beats)
    local brill = 0
    if c.lit then brill = clamp01((t - c.litAt) / 0.22) end
    scene:setMeshParams(c.ent, brill, 0, 0, 0)
  end
end
