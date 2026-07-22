-- PlayerMarker.lua -- 固定カメラでステージ全体を映すためプレイヤーが小さく見える。
-- 頭上にふわふわ浮かぶ黄色い▼マーカーを追従させ、現在地をひと目で分かるようにする。
-- 引き絞り中はモード色(シアン/紫)に変わり、いま何をしようとしているかも遠目に伝わる。
properties = {
  { name = "offsetY", type = "float", default = 1.25, min = 0.3, max = 4, label = "頭上オフセット" },
  { name = "bob",     type = "float", default = 0.12, min = 0,   max = 1, label = "上下ゆれ幅" },
}

function OnStart(self)
  self.t = 0
end

function OnUpdate(self, dt)
  self.t = self.t + dt
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local p = pl.transform.position
  local y = p.y + self.offsetY + math.sin(self.t * 3.2) * self.bob
  self.transform.position = Vec3.new(p.x, y, p.z - 0.15)

  -- 引き絞り中はビーム色と揃える(E=シアン / Q=紫)。平常時は黄色
  local e = scene:findEntity(self.name)
  if not (e and e:isValid()) then return end
  if keyDown("E") or padDown("X") then
    pcall(function() scene:setSpriteColor(e, 0.35, 0.85, 1.0, 0.95) end)
  elseif keyDown("Q") or padDown("LB") then
    pcall(function() scene:setSpriteColor(e, 0.7, 0.5, 1.0, 0.95) end)
  else
    pcall(function() scene:setSpriteColor(e, 1.0, 0.85, 0.25, 0.9) end)
  end
end
