-- Beacon.lua -- 撃てる対象(的/ボタン/錠など)の頭上でふわふわ明滅するマーカー。
-- 広いステージでも「どこを撃てばいいか」がひと目で分かるようにする。
-- 対象が消えたら(退避/破壊)自分も隠れる。色はスプライト側の color で指定する。
properties = {
  { name = "targetName", type = "string", default = "",   label = "追従する対象エンティティ名" },
  { name = "offsetY",    type = "float",  default = 1.2,  min = 0.2, max = 6, label = "対象からの高さ" },
  { name = "bob",        type = "float",  default = 0.15, min = 0,   max = 1, label = "上下ゆれ幅" },
}

function OnStart(self)
  self.t = math.random() * 3.14
end

function OnUpdate(self, dt)
  self.t = self.t + dt
  local e = scene:findEntity(self.targetName)
  if not (e and e:isValid()) then return end
  local p = e.transform.position
  local s = e.transform.scale
  if p.y < -50 then
    self.transform.position = Vec3.new(0, -100, 0)   -- 対象が退避中は隠す
    return
  end
  local y = p.y + s.y * 0.5 + self.offsetY + math.sin(self.t * 2.6) * self.bob
  self.transform.position = Vec3.new(p.x, y, p.z - 0.1)
  -- ゆっくり明滅(スプライトαのみ揺らす)
  local me = scene:findEntity(self.name)
  if me and me:isValid() then
    pcall(function() scene:setSpriteAlpha(me, 0.65 + 0.3 * math.sin(self.t * 3.5)) end)
  end
end
