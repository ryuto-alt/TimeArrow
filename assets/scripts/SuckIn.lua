-- SuckIn.lua -- 「背景の崩壊によって奥に吸い込まれるオブジェクト」。BackgroundCollapse.lua が
-- 規定の崩壊度に達すると発行する events:emit("bg_collapsed") を受けて、縮みながら奥へ消える。
properties = {
  { name = "shrinkTime", type = "float", default = 0.8, min = 0.1, max = 5, label = "吸い込まれる所要時間" },
}

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  local s = self.transform.scale
  self.baseScaleX, self.baseScaleY, self.baseScaleZ = s.x, s.y, s.z
  self.sucking = false
  self.t = 0

  events:on("bg_collapsed", function()
    if self.sucking then return end
    self.sucking = true
    FX.spark(self.bx, self.by, self.bz, 12, 0.4, 0.4, 0.5)
  end)
end

function OnUpdate(self, dt)
  if not self.sucking then return end
  self.t = self.t + dt
  local frac = clamp(self.t / self.shrinkTime, 0, 1)
  local sc = 1 - frac
  self.transform.scale = Vec3.new(self.baseScaleX * sc, self.baseScaleY * sc, self.baseScaleZ)
  self.transform.position = Vec3.new(self.bx, self.by, self.bz + frac * 6)
  if frac >= 1 then
    self.transform.position = Vec3.new(self.bx, -100, self.bz)
  end
end
