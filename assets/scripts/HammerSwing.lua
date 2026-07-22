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

  local R = 2.35 * self.transform.scale.y
  local rad = math.rad(ang)
  local hx = self.bx + math.sin(rad) * R
  local hy = self.by - math.cos(rad) * R

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0  -- 撃てる=金色の的アピール
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow > 0 then eff = 2.8 end
    scene:setMeshEffect(selfE, eff)
  end
  if self.ffRemain > 0 then FX.trail(hx, hy, self.bz, 0.3, 0.9, 1.0) end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(hx, hy, self.bz, 0.65, 0.4, 1.0)
  end

  if self.ffRemain > 0 then return end   -- 早送り中は経由位相で殺さない
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp = pl.transform.position
  if math.abs(pp.x - hx) < (self.hitHalf + 0.4) and math.abs(pp.y - hy) < (self.hitHalf + 0.45) then
    events:emit("player_died", {})
  end
end
