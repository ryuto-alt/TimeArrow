-- TargetGlow.lua -- 矢を当てられる静的オブジェクト(的/ボタン等)に金色の的アピールを付ける。
properties = {}

function OnStart(self)
  self.applied = false
end

function OnUpdate(self, dt)
  if self.applied then return end
  local e = scene:findEntity(self.name)
  if e and e:isValid() then
    scene:setMeshEffect(e, 5.0)
    self.applied = true
  end
end
