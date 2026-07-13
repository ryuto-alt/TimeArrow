-- Button.lua -- プレイヤーが乗る、または矢を刺すことで押せるボタン。
-- skipAmount>0 なら連動先へ events:emit("time_skip", {target=linkTarget, amount=skipAmount}) を送り、
-- 先送り演出(ビーム/火花/衝撃波+ゴーストタイムの半透明化)ごと連動先(CrushWall等)を動かす。
-- skipAmount=0 のときは従来通り events:emit("button_toggle", {target=linkTarget}) で動作/停止をトグルする。
properties = {
  { name = "linkTarget", type = "string", default = "",   label = "連動先エンティティ名" },
  { name = "standOn",    type = "bool",   default = true, label = "プレイヤーが乗ると押せる" },
  { name = "arrowHit",   type = "bool",   default = true, label = "矢を刺すと押せる(Player.targetsに登録要)" },
  { name = "skipAmount", type = "float",  default = 0.0,  min = 0, max = 30, label = "連動先へ送る先送り量(0ならbutton_toggleを送る)" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

local function press(self)
  if self.linkTarget ~= "" then
    if self.skipAmount > 0 then
      events:emit("time_skip", { target = self.linkTarget, amount = self.skipAmount })
    else
      events:emit("button_toggle", { target = self.linkTarget })
    end
  end
  FX.spark(self.bx, self.by, self.bz, 10, 1.0, 0.85, 0.3)
  fx:pulse(0.12)
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.wasStanding = false

  events:on("time_skip", function(data)
    if data.target ~= self.name or not self.arrowHit then return end
    press(self)
  end)
end

function OnUpdate(self, dt)
  local standing = false
  if self.standOn then
    local s = self.transform.scale
    local pl = scene:findEntity("Player")
    if pl and pl:isValid() then
      local pp, ps = pl.transform.position, pl.transform.scale
      standing = overlapAABB(self.bx, self.by, s.x * 0.5, s.y * 0.5, pp.x, pp.y, ps.x * 0.5, ps.y * 0.5)
    end
  end
  if standing and not self.wasStanding then press(self) end
  self.wasStanding = standing

  self.transform.position = Vec3.new(self.bx, standing and (self.by - 0.08) or self.by, self.bz)
end
