-- CameraFollow.lua -- GameCamera に付けるプレイヤー追従カメラ。
-- ステージ広域化でプレイヤーが小さくなったため、固定全景をやめてズームインで追従する。
-- X はステージ端でクランプ(端の外の虚無を映さない)、Y は高所(デッキ)に上がると付いていく。
properties = {
  { name = "dist",    type = "float", default = 9.5, min = 4,  max = 30, label = "カメラ距離(小さいほど寄る)" },
  { name = "offsetY", type = "float", default = 4.35, min = 0, max = 10, label = "プレイヤーからの高さオフセット(俯角14°で画面下40%に立つ値)" },
  { name = "minX",    type = "float", default = 8.1,            label = "左クランプ(ステージ左端+視界半幅)" },
  { name = "maxX",    type = "float", default = 20.0,           label = "右クランプ(ステージ右端-視界半幅)" },
  { name = "minY",    type = "float", default = 4.9,            label = "下クランプ(地上フロアの基準框)" },
  { name = "smooth",  type = "float", default = 6.0, min = 1, max = 20, label = "追従の滑らかさ(大きいほど機敏)" },
}

function OnStart(self)
  local p = self.transform.position
  self.cx, self.cy = p.x, p.y
end

function OnUpdate(self, dt)
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp = pl.transform.position
  local tx = clamp(pp.x, self.minX, self.maxX)
  local ty = math.max(self.minY, pp.y + self.offsetY)
  local k = math.min(1.0, dt * self.smooth)
  self.cx = self.cx + (tx - self.cx) * k
  self.cy = self.cy + (ty - self.cy) * k
  self.transform.position = Vec3.new(self.cx, self.cy, -self.dist)
  self.transform.rotation = Vec3.new(14.0, 0.0, 0.0)
end
