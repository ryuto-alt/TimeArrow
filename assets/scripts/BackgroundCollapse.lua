-- BackgroundCollapse.lua -- Backdropに貼る。仕様書「シークバーと共に時間が迫ると奥の壁も
-- 崩れていくようにする(規則的ではなくランダムに)」を実現する。GameManagerとは独立に自分の時計を
-- 持つ(共有状態を使わない既存の流儀通り)。崩壊が進むと SuckIn.lua 宛に events:emit("bg_collapsed")。
-- 壁本体の見た目は shaders/BackdropCollapse.hlsl(正方形セル単位の崩壊、マテリアル/ライティングは維持)
-- が担い、scene:setMeshEffect(self, intensity) で経過割合を毎フレーム送って同期させる。
properties = {
  { name = "T",          type = "float", default = 10.0, min = 1, max = 60, label = "このステージの制限時間(GameManagerと合わせる)" },
  { name = "collapseAt", type = "float", default = 0.5,  min = 0, max = 1,  label = "崩壊エフェクトを始める経過割合(0-1)" },
  { name = "suckInAt",   type = "float", default = 0.75, min = 0, max = 1,  label = "吸い込みイベントを発行する経過割合" },
}

function OnStart(self)
  local p = self.transform.position
  local s = self.transform.scale
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.halfW, self.halfH = s.x * 0.5, s.y * 0.5
  self.clock = 0
  self.emitAccum = 0
  self.suckFired = false
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  local frac = clamp(self.clock / self.T, 0, 1)

  local intensity = 0
  if frac >= self.collapseAt then
    intensity = (frac - self.collapseAt) / math.max(1 - self.collapseAt, 0.001)
  end

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    scene:setMeshEffect(selfE, intensity)
  end

  if frac < self.collapseAt then return end

  self.emitAccum = self.emitAccum + dt * (1 + intensity * 6)
  if self.emitAccum > 0.15 then
    self.emitAccum = 0
    local rx = self.bx + (math.random() - 0.5) * self.halfW * 1.8
    local ry = self.by + (math.random() - 0.5) * self.halfH * 1.8
    fx:burst{ x = rx, y = ry, z = self.bz - 0.3, count = 4, kind = "smoke",
              size = 0.5, sizeEnd = 0.0, life = 0.5, gravity = -1.0, r = 0.3, g = 0.3, b = 0.35 }
    FX.spark(rx, ry, self.bz - 0.3, 3, 0.5, 0.5, 0.55)
  end

  if not self.suckFired and frac >= self.suckInAt then
    self.suckFired = true
    events:emit("bg_collapsed", {})
  end
end
