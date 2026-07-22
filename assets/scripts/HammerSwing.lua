-- HammerSwing.lua -- 支点(モデル原点=上端)を中心に振り子運動するハンマー(Hammer_Pendulum)。
-- 直線ノコと違い、通路を塞ぐのは振り下ろしの一瞬だけ=平地でもタイミングで渡れる。
-- 先送り矢: 位相スキップ(振りを手繰る)。後戻り矢: 位相を戻す+返金(古い時計=良い銀行)。
-- headDist はモデルのヘッド位置(2.35)×transform.scale.y で自動計算する。
properties = {
  { name = "period",     type = "float", default = 3.2, min = 0.8, max = 12, label = "振り周期(秒)" },
  { name = "maxAngle",   type = "float", default = 55.0, min = 10, max = 85, label = "最大振り角(度)" },
  { name = "startPhase", type = "float", default = 0.0, min = 0,   max = 20, label = "開始位相(秒)" },
  { name = "hitHalf",    type = "float", default = 0.42, min = 0.2, max = 2, label = "ヘッドの当たり半径" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = self.startPhase
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx, self.by, self.bz, 8, 0.3, 0.75, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 0.5
    self.rwGlow = 0.1
    FX.spark(self.bx, self.by, self.bz, 10, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.65, 0.4, 1.0)
  end)

end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)
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

  local ang = self.maxAngle * math.sin((self.clock / self.period) * math.pi * 2)
  self.transform.rotation = Vec3.new(0, 0, ang)

  -- ヘッド位置(支点からscale.y×2.35下、角度分振れる)
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

  -- 早送り中は経由位相で殺さない(ワープ扱い)
  if self.ffRemain > 0 then return end
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp, ps = pl.transform.position, pl.transform.scale
  if math.abs(pp.x - hx) < (self.hitHalf + 0.4) and math.abs(pp.y - hy) < (self.hitHalf + 0.45) then
    events:emit("player_died", {})
  end
end
