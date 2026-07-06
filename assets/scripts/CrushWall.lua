-- CrushWall.lua -- 「動く壁」= 本物の障害物。startT から axis 方向へ動きながら、常に
-- Player.solids 経由で物理的に通行不可(触れて死ぬのではなく、そもそも通れない)。
-- 矢で先送りされると、動いている途中の位置を"すっ飛ばして"未来の位置へワープする。
-- ワープ中(ghostTime秒)は実体ごと退避して物理ブロックが外れる(=フェーズアウトしてすり抜けられる)。
-- 「どこからどこへ飛んだか」が一目で分かるよう、移動元→移動先を結ぶ軌跡ビーム+着地点を予告する
-- 明滅マーカー(fx:beam/fx:burst)に加え、再出現の瞬間は shaders/dissolve.hlsl (Sprite2D カスタム
-- シェーダー、scene:setSpriteEffect で effectValue=1→0 を送る)でノイズ状に実体化する演出を重ねる。
properties = {
  { name = "startT",      type = "float", default = 2.0,  min = 0,   max = 60, label = "動き出す時刻(秒)" },
  { name = "axisX",       type = "float", default = -1.0, min = -1,  max = 1,  label = "進む向き(-1=左 / 1=右)" },
  { name = "speed",       type = "float", default = 1.2,  min = 0.1, max = 10, label = "進む速さ" },
  { name = "travel",      type = "float", default = 14.0, min = 0,   max = 60, label = "総移動距離" },
  { name = "ghostTime",   type = "float", default = 0.35, min = 0.05,max = 2,  label = "先送り直後にすり抜けられる時間" },
  { name = "materializeTime", type = "float", default = 0.25, min = 0.05, max = 1, label = "再出現時にディゾルブで実体化する時間" },
  { name = "listenButton",type = "bool",  default = false,                    label = "ボタン連動(押すたび動作/停止を切替)" },
}

local function posAt(self, clockValue)
  local maxElapsed = self.travel / self.speed
  local elapsed = math.max(0, math.min(clockValue - self.startT, maxElapsed))
  return self.bx + self.axisX * self.speed * elapsed
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.ghostT = 0
  self.buttonActive = true
  self.landX = self.bx
  self.markerAccum = 0
  self.materializeT = 0  -- >0の間、再出現直後のディゾルブ実体化フェードを再生中

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    local oldX = posAt(self, self.clock)
    self.clock = self.clock + data.amount
    local newX = posAt(self, self.clock)
    self.ghostT = self.ghostTime
    self.landX = newX

    -- 移動元→移動先を結ぶ光の軌跡(距離がひと目で分かる)+ 両端の衝撃波
    fx:beam{ x0 = oldX, y0 = self.by, z0 = self.bz, x1 = newX, y1 = self.by, z1 = self.bz,
             width = 0.3, r = 0.35, g = 0.85, b = 1.0, intensity = 5.5, life = self.ghostTime + 0.15,
             kind = "energy" }
    fx:burst{ x = (oldX + newX) * 0.5, y = self.by, z = self.bz, count = 18, kind = "spark",
              dx = (newX > oldX) and 1 or -1, dy = 0, dz = 0, spread = 0.25,
              speed = math.abs(newX - oldX) * 2.5 + 5, speedVar = 0.4,
              size = 0.2, sizeEnd = 0.0, life = 0.4, r = 0.4, g = 0.9, b = 1.0 }
    FX.shockwave(oldX, self.by, self.bz, 14, 6, 0.3, 0.75, 1.0)
    FX.shockwave(newX, self.by, self.bz, 16, 9, 0.5, 0.95, 1.0)
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

  local wasGhosting = self.ghostT > 0
  if self.ghostT > 0 then self.ghostT = self.ghostT - dt end
  if wasGhosting and self.ghostT <= 0 then
    self.materializeT = self.materializeTime  -- ちょうど今フレームで戻ってきた=実体化フェード開始
  end

  local nx = posAt(self, self.clock)
  local dissolveAmount = 0

  if self.ghostT > 0 then
    self.transform.position = Vec3.new(nx, -100, self.bz)  -- フェーズアウト中=物理ブロックから外れる
    dissolveAmount = 1.0
    -- 再出現する場所を明滅マーカーで予告(どこへ着地するか一目で分かる)
    self.markerAccum = self.markerAccum + dt
    if self.markerAccum > 0.06 then
      self.markerAccum = 0
      fx:burst{ x = self.landX, y = self.by, z = self.bz, count = 2, kind = "glow",
                size = 0.5, sizeEnd = 0.0, life = 0.2, r = 0.5, g = 0.9, b = 1.0 }
    end
  else
    self.transform.position = Vec3.new(nx, self.by, self.bz)
    if self.materializeT > 0 then
      self.materializeT = self.materializeT - dt
      dissolveAmount = clamp(self.materializeT / self.materializeTime, 0, 1)
    end
  end

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    scene:setSpriteEffect(selfE, dissolveAmount)
  end
end
