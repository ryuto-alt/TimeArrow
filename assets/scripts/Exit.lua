-- Exit.lua -- ゴール(階段アイコン)。Player が近づくと次のシーンへ。
properties = {
  { name = "radius", type = "float",  default = 1.2, min = 0.3, max = 5, label = "到達判定半径" },
  { name = "next",   type = "string", default = "scenes/title.json",     label = "遷移先シーン" },
}

function OnStart(self)
  self.done = false
end

function OnUpdate(self, dt)
  if self.done then return end
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local me, pp = self.transform.position, pl.transform.position
  local dx, dy = me.x - pp.x, me.y - pp.y
  if dx * dx + dy * dy < self.radius * self.radius then
    self.done = true
    goToScene(self.next, 0.6)
  end
end
