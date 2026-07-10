-- Exit.lua -- ゴール(旗アイコン)。Player が近づくと次のシーンへ。
-- RollBall等が「ゴールを守れなかった」場合は events:emit("goal_broken") で破壊され、
-- 以後どれだけ触れても先へは進めない(=順序を間違えると詰む。GameManagerのタイムアップ待ちになる)。
properties = {
  { name = "radius", type = "float",  default = 1.2, min = 0.3, max = 5, label = "到達判定半径" },
  { name = "next",   type = "string", default = "scenes/title.json",     label = "遷移先シーン" },
}

function OnStart(self)
  self.done = false
  self.broken = false
  events:on("goal_broken", function()
    if self.broken then return end
    self.broken = true
    local p = self.transform.position
    FX.explosion(p.x, p.y, p.z, 1.1, 0.9, 0.4, 0.2)
    fx:pulse(0.5)
  end)
end

function OnUpdate(self, dt)
  if self.done then return end
  if self.broken then
    ui:text(20, 50, "GOAL DESTROYED...", 20, 1.0, 0.4, 0.3, 1)
    return
  end
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local me, pp = self.transform.position, pl.transform.position
  local dx, dy = me.x - pp.x, me.y - pp.y
  if dx * dx + dy * dy < self.radius * self.radius then
    self.done = true
    goToScene(self.next, 0.6)
  end
end
