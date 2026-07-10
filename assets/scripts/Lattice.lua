-- Lattice.lua -- 「矢がすり抜ける格子」。プレイヤーの Player.solids に自分の名前を入れると
-- 物理的に通れない壁になるが、Player.targets には入れない(矢はすり抜けて奥へ飛んでいく=判定なし)。
-- listenButton=true ならボタンでこの格子自体を退避させて通行可にできる。
properties = {
  { name = "listenButton", type = "bool",  default = false,                 label = "ボタンで開閉する" },
  { name = "hideY",        type = "float", default = -100, min = -200, max = 0, label = "開いた時に退避するY" },
}

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.opened = false

  events:on("button_toggle", function(data)
    if data.target ~= self.name or not self.listenButton then return end
    self.opened = not self.opened
    FX.spark(self.bx, self.by, self.bz, 10, 0.6, 0.9, 0.4)
  end)
end

function OnUpdate(self, dt)
  local y = self.opened and self.hideY or self.by
  self.transform.position = Vec3.new(self.bx, y, self.bz)
end
