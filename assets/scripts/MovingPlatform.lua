-- MovingPlatform.lua -- period周期でY方向(上下)に往復する足場。矢で先送りすると位相がずれる
-- (=タイミングを手繰り寄せて乗りやすい位相へ持っていける)。Player.standablesに名前を登録すれば乗れる。
-- Pendulum.lua(X方向版)のY方向版。deadly判定は持たない(足場専用)。
properties = {
  { name = "period",      type = "float", default = 5.0, min = 0.3, max = 20, label = "往復周期(秒)" },
  { name = "amplitude",   type = "float", default = 1.5, min = 0,   max = 10, label = "振れ幅(上下)" },
  { name = "startPhase",  type = "float", default = 0.0, min = 0,   max = 20, label = "開始位相オフセット(秒)" },
}

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = self.startPhase
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    -- 一括加算せず早送り(0.5秒で消化)して、足場が高速で動いて見えるようにする
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx, self.transform.position.y, self.bz, 8, 0.3, 0.75, 1.0)
  end)
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  local ang = math.sin((self.clock / self.period) * math.pi * 2)
  local ny = self.by + ang * self.amplitude
  self.transform.position = Vec3.new(self.bx, ny, self.bz)

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    scene:setSpriteAlpha(selfE, self.ffRemain > 0 and 0.45 or 1.0)
  end
end
