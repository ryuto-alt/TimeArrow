-- Button.lua -- プレイヤーが乗る、または矢を刺すことで押せるボタン。
-- 押すたびに events:emit("button_toggle", {target=linkTarget}) を発行して連動先(壁/リフト/格子/扉)を
-- トグルする。連動先は各スクリプトの listenButton=true + button_toggle 受信で反応する。
properties = {
  { name = "linkTarget", type = "string", default = "",   label = "連動先エンティティ名" },
  { name = "standOn",    type = "bool",   default = true, label = "プレイヤーが乗ると押せる" },
  { name = "arrowHit",   type = "bool",   default = true, label = "矢を刺すと押せる(Player.targetsに登録要)" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

local function press(self)
  if self.linkTarget ~= "" then
    events:emit("button_toggle", { target = self.linkTarget })
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
