-- TitleLogoMotion.lua -- タイトルロゴの浮遊モーション。
-- ゆっくり上下にふわふわ + わずかに傾きを揺らして「時を先送りする矢」の浮遊感を出す。
properties = {
  { name = "floatAmp",   type = "float", default = 0.25, min = 0, max = 3,  label = "上下の振れ幅" },
  { name = "floatSpeed", type = "float", default = 0.5,  min = 0, max = 5,  label = "上下の速さ(Hz)" },
  { name = "swayDeg",    type = "float", default = 2.5,  min = 0, max = 30, label = "傾きの振れ幅(度)" },
  { name = "swaySpeed",  type = "float", default = 0.35, min = 0, max = 5,  label = "傾きの速さ(Hz)" },
}

function OnStart(self)
  local p = self.transform.position
  local r = self.transform.rotation
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.rx, self.ry, self.rz = r.x, r.y, r.z
  self.clock = 0
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  local t = self.clock * math.pi * 2
  local ny = self.by + math.sin(t * self.floatSpeed) * self.floatAmp
  self.transform.position = Vec3.new(self.bx, ny, self.bz)
  local nz = self.rz + math.sin(t * self.swaySpeed) * self.swayDeg
  self.transform.rotation = Vec3.new(self.rx, self.ry, nz)
end
