-- Wall.lua -- 見た目上は静的な壁/床(primitiveのまま、地形なので今回は変更対象外)。
-- Bomb.lua の wallTarget に自分の名前を指定してもらうと爆破で消えるようになる
-- (貼らなければ完全に無反応=ただの静的ジオメトリ)。
-- deadly=true にすると「爆破するまで触れると死ぬ瓦礫」として使える(当たり判定はtransform.scale基準)。
properties = {
  { name = "deadly",   type = "bool",  default = false, label = "破壊するまで接触で死亡" },
  { name = "hitScale", type = "float", default = 0.8,  min = 0.2, max = 1.5, label = "当たり判定の見た目に対する倍率" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.destroyed = false

  events:on("wall_destroyed", function(data)
    if data.target ~= self.name or self.destroyed then return end
    self.destroyed = true
    FX.spark(self.bx, self.by, self.bz, 16, 0.9, 0.7, 0.4)
    self.transform.position = Vec3.new(self.bx, -100, self.bz)
  end)
end

function OnUpdate(self, dt)
  if self.destroyed or not self.deadly then return end
  local s = self.transform.scale
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp, ps = pl.transform.position, pl.transform.scale
  if overlapAABB(self.bx, self.by, s.x * 0.5 * self.hitScale, s.y * 0.5 * self.hitScale, pp.x, pp.y, ps.x * 0.5, ps.y * 0.5) then
    events:emit("player_died", {})
  end
end
