-- HammerSwing.lua -- ゼンマイ仕掛けの振り子ハンマー(Hammer_Pendulum、原点=支点)。
-- 時間が経つほどゼンマイがほどけて振りが【遅く】なる(周期が伸びる)= 時間に実体がある。
--   先送り矢: 一気に老化 → 振りが鈍って安全窓が広がる=悠々と下を通れる(無力化の正解)
--   後戻し矢: ゼンマイが巻き戻って若返り、鋭い振りに戻る(+実効量の返金=銀行にもなる)
-- 直線ノコと違い、通路を塞ぐのは振り下ろしの一瞬だけ=タイミングで渡れる。
properties = {
  { name = "period",     type = "float", default = 3.2, min = 0.8, max = 12, label = "若い時の振り周期(秒)" },
  { name = "maxAngle",   type = "float", default = 55.0, min = 10, max = 85, label = "最大振り角(度)" },
  { name = "startPhase", type = "float", default = 0.0, min = 0,   max = 60, label = "開始時の年齢(秒)" },
  { name = "decayT",     type = "float", default = 25.0, min = 5,  max = 120,label = "この年齢で周期が2倍に伸びる(老化速度)" },
  { name = "hitHalf",    type = "float", default = 0.42, min = 0.2, max = 2, label = "ヘッドの当たり半径" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  events:on("aim_preview", function(d)
    if d.target == self.name or d.target == self.name .. "X" then
      self.aimPv = { m = d.mode, t = 0.12 }
    end
  end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = self.startPhase
  self.phase = 0            -- 振りの位相。周期が年齢で変わるため別積分
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name and data.target ~= self.name .. "X" then return end
    self.ffRemain = self.ffRemain + (data.amount or 0)
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx, self.by, self.bz, 10, 0.3, 0.75, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name and data.target ~= self.name .. "X" then return end
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 0.5
    self.rwGlow = 0.1
    FX.spark(self.bx, self.by, self.bz, 12, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.65, 0.4, 1.0)
  end)
end

-- 年齢→現在の周期(老いるほど遅い)。decayT歳で2倍、最大4倍まで伸びる
local function currentPeriod(self)
  local stretch = math.min(4.0, 1.0 + self.clock / self.decayT)
  return self.period * stretch
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)
  local before = self.clock
  self.clock = self.clock + dt
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  if self.rwRemain and self.rwRemain > 0 then
    local step = math.min(self.rwRemain, self.rwSpeed * dt, self.clock)
    if step <= 0 then
      self.rwRemain = 0
    else
      self.clock = self.clock - step
      self.rwRemain = self.rwRemain - step
      self.rwGlow = 0.1
      events:emit("time_refund", { amount = step })
    end
  end

  -- 位相は「その瞬間の周期」で進める(年齢が変わると振りの速さが目に見えて変わる)
  local dClock = self.clock - before
  self.phase = self.phase + dClock / currentPeriod(self)
  local ang = self.maxAngle * math.sin(self.phase * math.pi * 2)
  self.transform.rotation = Vec3.new(0, 0, ang)

  -- 経年劣化の見た目: 新品(〜0.8×decayT) / 摩耗(〜2×decayT) / 錆(それ以上)。
  -- FF/RWで年齢が動くとモデルも入れ替わる=時間操作が見た目で分かる
  local m2 = scene:findEntity(self.name .. "_m2")
  local m3 = scene:findEntity(self.name .. "_m3")
  if m2 and m2:isValid() and m3 and m3:isValid() then
    local stage = (self.clock < self.decayT * 0.8) and 1 or
                  ((self.clock < self.decayT * 2.0) and 2 or 3)
    -- 段階が変わった瞬間: 破片が弾けるフラッシュ(劣化/若返りの節目を見せる)
    if self.lastStage and stage ~= self.lastStage then
      local hy0 = self.by - 2.35 * self.transform.scale.y
      FX.shockwave(self.bx, hy0, self.bz, 14, 9, 0.75, 0.5, 0.3)
      FX.spark(self.bx, hy0, self.bz, 18, 0.6, 0.4, 0.25)
      fx:pulse(0.15)
    end
    self.lastStage = stage
    local ents = { scene:findEntity(self.name), m2, m3 }
    for i, e in ipairs(ents) do
      if e and e:isValid() then
        if i == 1 then
          -- 本体(判定/イベント持ち)は常に支点に置く。新品段階以外は見た目だけ隠す…はできないので
          -- 本体=新品モデル。段階2/3では本体を奥へ僅かに引っ込め、該当モデルを支点へ出す
          local show = (stage == 1)
          e.transform.position = Vec3.new(self.bx, show and self.by or -100, self.bz)
        else
          local show = (stage == i)
          e.transform.position = Vec3.new(self.bx, show and self.by or -100, self.bz)
          e.transform.rotation = Vec3.new(0, 0, ang)
          if show then
            local eff = 6.0 + math.min(0.95, self.clock / (self.decayT * 2.5))
            if self.ffRemain > 0 then eff = 1.0
            elseif self.rwGlow > 0 then eff = 2.8 end
            if self.aimPv and self.aimPv.t > 0 then
              eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
            end
            scene:setMeshEffect(e, eff)
          end
        end
      end
    end
  end

  local R = 2.35 * self.transform.scale.y
  local rad = math.rad(ang)
  local hx = self.bx + math.sin(rad) * R
  local hy = self.by - math.cos(rad) * R

  -- 劣化度(0=新品〜0.95=ぼろぼろ)をシェーダーへ: 錆の侵食+ヒビ+欠け落ち
  local deg = math.min(0.95, self.clock / (self.decayT * 2.5))
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 6.0 + deg
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow > 0 then eff = 2.8 end
    if self.aimPv then
      self.aimPv.t = self.aimPv.t - dt
      if self.aimPv.t > 0 then
        eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
      else
        self.aimPv = nil
      end
    end
    scene:setMeshEffect(selfE, eff)
  end
  if self.ffRemain > 0 then FX.trail(hx, hy, self.bz, 0.3, 0.9, 1.0) end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(hx, hy, self.bz, 0.65, 0.4, 1.0)
  end

  -- 火花: 摩耗以降、振りの最下点を通過する瞬間にガリッと研削火花が散る
  if self.lastStage and self.lastStage >= 2 then
    local s = math.sin(self.phase * math.pi * 2)
    if math.abs(s) < 0.10 then
      if not self.sparked then
        self.sparked = true
        local n = (self.lastStage == 3) and 40 or 22
        FX.spark(hx, hy - 0.4, self.bz, n, 1.0, 0.75, 0.2)
        FX.spark(hx, hy - 0.3, self.bz, n, 1.0, 0.5, 0.1)
        FX.spark(hx, hy - 0.5, self.bz, math.floor(n / 2), 1.0, 0.9, 0.4)
        FX.shockwave(hx, hy - 0.4, self.bz, 8, 5, 1.0, 0.6, 0.2)
        fx:pulse(self.lastStage == 3 and 0.1 or 0.05)
      end
    else
      self.sparked = false
    end
  end

  -- 劣化した個体は錆粉を撒き、末期はヨレて震える(見た目のみ。判定は本来の角度)
  if self.lastStage and self.lastStage >= 2 then
    self.dustT = (self.dustT or 0) + dt
    if self.dustT > (self.lastStage == 3 and 0.18 or 0.45) then
      self.dustT = 0
      FX.trail(hx + (math.random() - 0.5) * 0.6, hy - 0.3, self.bz, 0.55, 0.3, 0.12)
    end
    if self.lastStage == 3 then
      local wob = math.sin(self.phase * math.pi * 11) * 2.2   -- ガタつき
      local vis = scene:findEntity(self.name .. "_m3")
      if vis and vis:isValid() then
        vis.transform.rotation = Vec3.new(0, 0, ang + wob)
      end
      -- 常時火の粉シャワー(ヘッドから尾を引く)
      self.embT = (self.embT or 0) + dt
      if self.embT > 0.06 then
        self.embT = 0
        FX.spark(hx + (math.random() - 0.5) * 0.5, hy, self.bz, 3, 1.0, 0.55, 0.15)
      end
    end
  end

  if self.ffRemain > 0 then return end   -- 早送り中は経由位相で殺さない
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp = pl.transform.position
  if math.abs(pp.x - hx) < (self.hitHalf + 0.30) and math.abs(pp.y - hy) < (self.hitHalf + 0.42) then
    events:emit("player_died", {})
  end
end
