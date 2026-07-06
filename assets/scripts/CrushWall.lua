-- CrushWall.lua -- 「動く壁」= 本物の障害物。startT から axis 方向へ動きながら、常に
-- Player.solids 経由で物理的に通行不可(触れて死ぬのではなく、そもそも通れない)。
-- 矢で先送りされると、動いている途中の位置を"すっ飛ばして"未来の位置へワープする。
-- ワープ中(ghostTime秒)は実体ごと退避して物理ブロックが外れる(=フェーズアウトしてすり抜けられる)。
properties = {
  { name = "startT",      type = "float", default = 2.0,  min = 0,   max = 60, label = "動き出す時刻(秒)" },
  { name = "axisX",       type = "float", default = -1.0, min = -1,  max = 1,  label = "進む向き(-1=左 / 1=右)" },
  { name = "speed",       type = "float", default = 1.2,  min = 0.1, max = 10, label = "進む速さ" },
  { name = "travel",      type = "float", default = 14.0, min = 0,   max = 60, label = "総移動距離" },
  { name = "ghostTime",   type = "float", default = 0.35, min = 0.05,max = 2,  label = "先送り直後にすり抜けられる時間" },
  { name = "listenButton",type = "bool",  default = false,                    label = "ボタン連動(押すたび動作/停止を切替)" },
}

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.ghostT = 0
  self.buttonActive = true

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.clock = self.clock + data.amount
    self.ghostT = self.ghostTime
    FX.spark(self.transform.position.x, self.by, self.bz, 12, 0.3, 0.75, 1.0)
  end)

  events:on("button_toggle", function(data)
    if data.target ~= self.name or not self.listenButton then return end
    self.buttonActive = not self.buttonActive
  end)
end

function OnUpdate(self, dt)
  if not self.listenButton or self.buttonActive then
    self.clock = self.clock + dt
  end
  if self.ghostT > 0 then self.ghostT = self.ghostT - dt end

  local maxElapsed = self.travel / self.speed
  local elapsed = math.max(0, math.min(self.clock - self.startT, maxElapsed))
  local nx = self.bx + self.axisX * self.speed * elapsed

  if self.ghostT > 0 then
    self.transform.position = Vec3.new(nx, -100, self.bz)  -- フェーズアウト中=物理ブロックから外れる
  else
    self.transform.position = Vec3.new(nx, self.by, self.bz)
  end
end
