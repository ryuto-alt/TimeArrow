-- Exit.lua -- ゴール(時計仕掛けの出口ゲート、Blender自作 Exit_Door)。中で ExitRing
-- (シアンの環)が回り続け、上昇する火花で「ここが出口」と視覚的に主張する。
-- 判定は Player.lua と同じ流儀の AABB(プレイヤー半幅0.34/半高0.55 × ゲート開口部)。
-- 到達で祝福FX → "stage_cleared"。RollBall 等に轢かれると events "goal_broken" で
-- 破壊され、以後は触れても進めない(=順序を間違えると詰む)。
properties = {
  { name = "halfW", type = "float",  default = 0.80, min = 0.2, max = 4, label = "到達判定の半幅" },
  { name = "halfH", type = "float",  default = 0.90, min = 0.2, max = 4, label = "到達判定の半高" },
  { name = "next",  type = "string", default = "scenes/title.json",      label = "遷移先シーン" },
}

local PHW, PHH = 0.34, 0.55   -- プレイヤーの当たり半幅/半高(Player.luaと一致させる)

function OnStart(self)
  self.done = false
  self.broken = false
  self.clock = 0
  self.emitT = 0
  self.ringSpin = 0
  self.ring = scene:findEntity("ExitRing")
  events:on("goal_broken", function()
    if self.broken then return end
    self.broken = true
    local p = self.transform.position
    FX.explosion(p.x, p.y, p.z, 1.1, 0.9, 0.4, 0.2)
    fx:pulse(0.5)
    -- 扉は黒焦げ、環は砕けて消える
    local me = scene:findEntity(self.name)
    if me and me:isValid() then scene:setColor(me, 0.25, 0.2, 0.22) end
    if self.ring and self.ring:isValid() then
      self.ring.transform.position = Vec3.new(0, -200, 0)
    end
    events:emit("stage_goal_ruined", {})
  end)
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  local p = self.transform.position

  -- 環の回転(通常はゆっくり、クリア後は加速)+呼吸するスケール
  if self.ring and self.ring:isValid() and not self.broken then
    local rate = self.done and 540 or 55
    self.ringSpin = self.ringSpin + rate * dt
    self.ring.transform.rotation = Vec3.new(0, 0, self.ringSpin)
    local s = 1.15 * (1 + 0.06 * math.sin(self.clock * 2.2))
    self.ring.transform.scale = Vec3.new(s, s, s)
  end

  if self.broken then
    -- 壊れたゴール: 黒煙がくすぶる
    self.emitT = self.emitT + dt
    if self.emitT > 0.5 then
      self.emitT = 0
      fx:burst{ x = p.x, y = p.y + 0.4, z = p.z - 0.2, count = 2, kind = "smoke",
                size = 0.35, sizeEnd = 0.0, life = 0.8, gravity = -0.8,
                r = 0.15, g = 0.13, b = 0.15 }
    end
    return
  end

  -- ポータルから立ちのぼるシアンの火花(出口の目印)
  self.emitT = self.emitT + dt
  if self.emitT > 0.22 and not self.done then
    self.emitT = 0
    local ox = (math.random() - 0.5) * 0.8
    FX.trail(p.x + ox, p.y - 0.5 + math.random() * 0.6, p.z - 0.1, 0.35, 0.9, 1.0)
  end

  if self.done then return end
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp = pl.transform.position
  if math.abs(pp.x - p.x) < (self.halfW + PHW) and math.abs(pp.y - p.y) < (self.halfH + PHH) then
    self.done = true
    -- 祝福: 環が急加速し、シアンの衝撃波+火花の噴水
    FX.shockwave(p.x, p.y, p.z, 14, 8, 0.4, 0.95, 1.0)
    FX.spark(p.x, p.y + 0.3, p.z - 0.2, 26, 0.5, 0.95, 1.0)
    fx:burst{ x = p.x, y = p.y, z = p.z - 0.2, count = 12, kind = "spark",
              size = 0.22, life = 0.7, speed = 5, r = 1.0, g = 0.9, b = 0.4 }
    events:emit("stage_cleared", { next = self.next })
  end
end