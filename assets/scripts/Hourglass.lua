-- Hourglass.lua -- 時の砂時計=「銀行」ステーション(Hourglassモデル)。
-- 置いてある間ずっと砂(時計)が積もり続ける。後戻り矢を当てると積もった分だけ
-- 制限時間が返金される(実効量×0.5)。返金の仕組みを見える形で教える専用ギミック。
-- 先送り矢: 砂が一気に積もる(=後で戻せる貯金になる。ただし先送りの代償も払うので±0)。
properties = {
  { name = "spinSpeed", type = "float", default = 20.0, min = 0, max = 120, label = "ゆっくり回る見た目の速度" },
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
  self.clock = 0
  self.ffRemain = 0
  self.spin = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx, self.by, self.bz, 10, 0.3, 0.75, 1.0)
  end)

  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 0.5
    self.rwGlow = 0.15
    FX.spark(self.bx, self.by, self.bz, 12, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 12, 7, 0.65, 0.4, 1.0)
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
      self.rwGlow = 0.15
      events:emit("time_refund", { amount = step })
    end
  end

  self.spin = self.spin + dt * self.spinSpeed
  self.transform.rotation = Vec3.new(0, self.spin % 360, 0)

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0  -- 撃てる=金色の的アピール
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
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(self.bx, self.by + 0.4, self.bz, 0.65, 0.4, 1.0)
  end
  -- 砂が積もっているほど金色に光る(残量が見える)
  self.fxT = (self.fxT or 0) + dt
  if self.fxT > math.max(0.15, 1.2 - self.clock * 0.02) then
    self.fxT = 0
    FX.trail(self.bx, self.by + 0.2, self.bz, 1.0, 0.8, 0.3)
  end
end
