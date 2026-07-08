-- GrowVine.lua -- growT から根元(bottomY)を固定したまま上へ育つ蔦。育ちきる前は小さすぎて
-- Player の登り判定(AABB)に重ならない=触れられない。矢で先送りすると即座に育つ。
-- unitHeight は Sprite2D.size.y をそのまま数値で持たせておく(Luaからsize自体は読めないため)。
properties = {
  { name = "growT",        type = "float", default = 3.0,  min = 0,    max = 60, label = "育ち始める時刻(秒)" },
  { name = "growDuration",  type = "float", default = 1.0,  min = 0.1,  max = 10, label = "育つのにかかる時間" },
  { name = "bottomY",       type = "float", default = 0.0,                        label = "根元のY(地面)" },
  { name = "unitHeight",    type = "float", default = 3.0,  min = 0.2,  max = 20, label = "scale=1の時の高さ(Sprite2D.sizeのYと合わせる)" },
}

local function applyGrowth(self, frac)
  local scaleY = math.max(0.04, frac) * self.baseScaleY
  self.transform.scale = Vec3.new(self.baseScaleX, scaleY, self.baseScaleZ)
  self.transform.position = Vec3.new(self.bx, self.bottomY + (scaleY * self.unitHeight) * 0.5, self.bz)
  self.grown = frac >= 1.0
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.bz = p.x, p.z
  local s = self.transform.scale
  self.baseScaleX, self.baseScaleY, self.baseScaleZ = s.x, s.y, s.z
  self.clock = 0
  self.ffRemain = 0
  applyGrowth(self, 0)

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    -- 一括加算せず早送り(0.5秒で消化)して、育つ様子が見えるようにする
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.transform.position.x, self.transform.position.y, self.bz, 10, 0.6, 0.9, 0.4)
  end)
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  local frac = clamp((self.clock - self.growT) / self.growDuration, 0, 1)
  applyGrowth(self, frac)

  -- 早送り中は半透明(=実体がない「経由中」の表現)
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    scene:setSpriteAlpha(selfE, self.ffRemain > 0 and 0.45 or 1.0)
  end
end
