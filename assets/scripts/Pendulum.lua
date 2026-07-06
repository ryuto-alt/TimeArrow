-- Pendulum.lua -- period周期でX方向に振り子運動する足場/刃。矢で先送りすると位相がずれる
-- (=タイミングを手繰り寄せて安全な位相へ持っていける)。deadly=trueなら刃、falseなら足場として使う。
-- 当たり判定は自分の transform.scale から出すAABB。
properties = {
  { name = "period",      type = "float", default = 3.0, min = 0.3, max = 20, label = "往復周期(秒)" },
  { name = "amplitude",   type = "float", default = 3.0, min = 0,   max = 20, label = "振れ幅" },
  { name = "startPhase",  type = "float", default = 0.0, min = 0,   max = 20, label = "開始位相オフセット(秒)" },
  { name = "deadly",      type = "bool",  default = false,                    label = "刃として扱う(接触で死亡)" },
  { name = "hitScale",    type = "float", default = 0.8, min = 0.2, max = 1.5,label = "当たり判定の見た目に対する倍率" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = self.startPhase

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.clock = self.clock + data.amount
    FX.spark(self.transform.position.x, self.by, self.bz, 8, 0.3, 0.75, 1.0)
  end)
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  local ang = math.sin((self.clock / self.period) * math.pi * 2)
  local nx = self.bx + ang * self.amplitude
  self.transform.position = Vec3.new(nx, self.by, self.bz)

  if not self.deadly then return end
  local s = self.transform.scale
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp, ps = pl.transform.position, pl.transform.scale
  if overlapAABB(nx, self.by, s.x * 0.5 * self.hitScale, s.y * 0.5 * self.hitScale, pp.x, pp.y, ps.x * 0.5, ps.y * 0.5) then
    events:emit("player_died", {})
  end
end
