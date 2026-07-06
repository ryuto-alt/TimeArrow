-- Bomb.lua -- boomT に自爆し、隣接する Wall(wallTarget名)を破壊する。矢で先送りすると
-- 「遠くから安全に起爆」できる(=近くにいると爆風に巻き込まれる)。
-- 爆風は自分の transform.scale から出すAABBに blastScale 倍率をかけたもの。
properties = {
  { name = "boomT",      type = "float",  default = 12.0, min = 0,   max = 60, label = "起爆時刻(秒)" },
  { name = "blastScale", type = "float",  default = 2.2,  min = 1,   max = 6,  label = "爆風の広がり(自身の見た目サイズに対する倍率)" },
  { name = "wallTarget", type = "string", default = "",                        label = "破壊するWallの名前(任意)" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.exploded = false

  events:on("time_skip", function(data)
    if data.target ~= self.name or self.exploded then return end
    self.clock = self.clock + data.amount
    FX.spark(self.bx, self.by, self.bz, 10, 1.0, 0.7, 0.3)
  end)
end

function OnUpdate(self, dt)
  if self.exploded then return end
  self.clock = self.clock + dt
  if self.clock < self.boomT then return end

  self.exploded = true
  FX.explosion(self.bx, self.by, self.bz, 1.3, 1.0, 0.5, 0.15)
  fx:pulse(0.5)

  if self.wallTarget ~= "" then
    events:emit("wall_destroyed", { target = self.wallTarget })
  end

  local s = self.transform.scale
  local pl = scene:findEntity("Player")
  if pl and pl:isValid() then
    local pp, ps = pl.transform.position, pl.transform.scale
    if overlapAABB(self.bx, self.by, s.x * 0.5 * self.blastScale, s.y * 0.5 * self.blastScale,
                    pp.x, pp.y, ps.x * 0.5, ps.y * 0.5) then
      events:emit("player_died", {})
    end
  end
end
