-- TargetGlow.lua -- 矢を当てられる静的オブジェクト(的/ボタン等)の的アピール+照準ロック表示。
properties = {}

function OnStart(self)
  events:on("aim_preview", function(d)
    if d.target == self.name or d.target == self.name .. "X" then
      self.aimPv = { m = d.mode, t = 0.12 }
    end
  end)
end

function OnUpdate(self, dt)
  local e = scene:findEntity(self.name)
  if not (e and e:isValid()) then return end
  local eff = 5.0
  if self.aimPv then
    self.aimPv.t = self.aimPv.t - dt
    if self.aimPv.t > 0 then
      eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
    else
      self.aimPv = nil
    end
  end
  scene:setMeshEffect(e, eff)
end
