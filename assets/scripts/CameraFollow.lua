-- CameraFollow.lua -- GameCamera に付けるプレイヤー追従カメラ。
-- 通常は dist(視界約22u)で追従、TAB(パッドY)長押しでステージ全景へズームアウトする。
-- X はステージ端でクランプ、Y は高所(デッキ/最上層)に上がると付いていく。
properties = {
  { name = "dist",    type = "float", default = 13.0, min = 4,  max = 40, label = "追従時のカメラ距離" },
  { name = "offsetY", type = "float", default = 5.3,  min = 0,  max = 12, label = "プレイヤーからの高さオフセット" },
  { name = "minX",    type = "float", default = 11.1,           label = "左クランプ" },
  { name = "maxX",    type = "float", default = 30.0,           label = "右クランプ" },
  { name = "minY",    type = "float", default = 5.85,           label = "下クランプ" },
  { name = "smooth",  type = "float", default = 6.0, min = 1, max = 20, label = "追従の滑らかさ" },
  { name = "fullX",   type = "float", default = 0.0,            label = "全景ビューのカメラX" },
  { name = "fullY",   type = "float", default = 0.0,            label = "全景ビューのカメラY" },
  { name = "fullZ",   type = "float", default = -30.0,          label = "全景ビューのカメラZ" },
}

function OnStart(self)
  local p = self.transform.position
  self.cx, self.cy, self.cz = p.x, p.y, p.z
end

function OnUpdate(self, dt)
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local tx, ty, tz
  if keyDown("TAB") or padDown("Y") then
    -- 全景俯瞰(ステージを読む用)
    tx, ty, tz = self.fullX, self.fullY, self.fullZ
  else
    local pp = pl.transform.position
    tx = clamp(pp.x, self.minX, self.maxX)
    ty = math.max(self.minY, pp.y + self.offsetY)
    tz = -self.dist
  end
  local k = math.min(1.0, dt * self.smooth)
  self.cx = self.cx + (tx - self.cx) * k
  self.cy = self.cy + (ty - self.cy) * k
  self.cz = self.cz + (tz - self.cz) * k
  self.transform.position = Vec3.new(self.cx, self.cy, self.cz)
  self.transform.rotation = Vec3.new(14.0, 0.0, 0.0)
end
