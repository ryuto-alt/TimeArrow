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
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
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
    self.ffSpeed = self.ffRemain / 1.5   -- ゆっくり消化(サージが速すぎて避けられない問題への全体調整)
    FX.spark(self.transform.position.x, self.transform.position.y, self.bz, 10, 0.6, 0.9, 0.4)
  end)

  -- 後戻り(グローバル): 育った蔦も時間と一緒に縮む
  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    -- 後戻り矢: 一括減算せず逆再生(0.5秒で消化)して、巻き戻る様子を見せる
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 0.5
    self.rwGlow = 0.1
    local p = self.transform.position
    FX.spark(p.x, p.y, p.z, 10, 0.65, 0.4, 1.0)
    FX.shockwave(p.x, p.y, p.z, 10, 6, 0.65, 0.4, 1.0)
  end)
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)  -- 弓の構え中はスローモーション
  self.clock = self.clock + dt
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  if self.rwRemain and self.rwRemain > 0 then
    -- 対象の時計は0で底打ち。それ以上は戻せない=タイマー返金もされない(戻しすぎは無駄撃ち)
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
  local frac = clamp((self.clock - self.growT) / self.growDuration, 0, 1)
  applyGrowth(self, frac)

  -- 早送り中は半透明(=実体がない「経由中」の表現)
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    scene:setSpriteAlpha(selfE, self.ffRemain > 0 and 0.45 or 1.0)
  end

  -- 早送り=水色 / 後戻り=紫 の残像(先端に出す)
  local tip = self.transform.position
  if self.ffRemain > 0 then
    FX.trail(tip.x, tip.y, self.bz, 0.3, 0.9, 1.0)
  end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(tip.x, tip.y, self.bz, 0.65, 0.4, 1.0)
  end
end
