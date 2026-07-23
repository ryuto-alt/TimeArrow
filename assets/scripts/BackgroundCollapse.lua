-- BackgroundCollapse.lua -- 稜線帯(BackdropRidge*)に貼る。仕様書「シークバーと共に時間が
-- 迫ると奥の壁も崩れていくようにする」を実現する。時計は GameManager と同じ収支
-- (経過 dt×ts / 先送り=+量×0.5 即時 / 後戻り返金=-量×0.5)を鏡写しに持つので、
-- 矢で時間を進めれば背景も一気に崩れ、巻き戻せば崩れた背景が再生する。
-- 見た目は shaders/BackdropRidge.hlsl(ワールドXYセルの左→右崩壊)が担い、
-- scene:setMeshEffect(self, 進行度) を毎フレーム送って同期させる。
-- 崩壊境界からは石の破片が飛び散る(境界X位置はシェーダーの線形式から逆算)。
properties = {
  { name = "T",          type = "float", default = 10.0, min = 1, max = 300, label = "このステージの制限時間(GameManagerと合わせる)" },
  { name = "collapseAt", type = "float", default = 0.0,  min = 0, max = 1,  label = "崩壊エフェクトを始める経過割合(0-1)" },
  { name = "suckInAt",   type = "float", default = 0.75, min = 0, max = 2,  label = "吸い込みイベントを発行する経過割合(>1で不発)" },
}

-- シェーダー(BackdropRidge.hlsl)の崩壊境界: threshold=lerp(-0.1,1.1,p), x=(threshold*120)-15
local function boundaryX(progress)
  return (progress * 1.2 - 0.1) * 120.0 - 15.0
end

local function debris(x, y, z, n)
  -- 石の破片: 右上へ弾け飛んで重力で落ちる欠片+シアンの時の粒子
  fx:burst{ x = x, y = y, z = z, count = n, kind = "smoke",
            dx = 0.75, dy = 0.55, dz = -0.15, spread = 0.75,
            speed = 5.5, speedVar = 0.6, size = 0.28, sizeEnd = 0.05,
            life = 0.9, lifeVar = 0.4, gravity = -11.0, drag = 0.6,
            r = 0.30, g = 0.32, b = 0.40 }
  fx:burst{ x = x, y = y, z = z - 0.2, count = math.max(2, math.floor(n / 2)),
            kind = "spark", dx = 0.5, dy = 0.8, dz = 0, spread = 0.9,
            speed = 4.0, speedVar = 0.7, size = 0.14, sizeEnd = 0.0,
            life = 0.55, gravity = -4.0, r = 0.35, g = 0.8, b = 1.0 }
end

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  local p = self.transform.position
  local s = self.transform.scale
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.halfW, self.halfH = s.x * 0.5, s.y * 0.5
  self.clock = 0
  self.emitAccum = 0
  self.suckFired = false

  -- 世界タイマーと同じ収支(GameManager.luaと同係数)。先送りで背景も一気に崩れる
  events:on("time_skip", function(data)
    local before = clamp(self.clock / self.T, 0, 1)
    self.clock = self.clock + (data.amount or 0) * 0.5
    local after = clamp(self.clock / self.T, 0, 1)
    -- 崩壊境界がこの帯を通過した区間に破片をまとめて散らす(ドカッと崩れた感)
    local x0, x1 = boundaryX(before), boundaryX(after)
    local lo, hi = self.bx - self.halfW, self.bx + self.halfW
    if x1 > lo and x0 < hi then
      local a, b = math.max(x0, lo), math.min(x1, hi)
      for i = 0, 2 do
        local rx = a + (b - a) * (i + math.random()) / 3
        debris(rx, self.by + (math.random() - 0.5) * self.halfH * 1.4, self.bz - 0.3, 8)
      end
    end
  end)
  -- 後戻りの返金分だけ背景も再生する(シェーダーは進行度の純関数なので戻せば蘇る)
  events:on("time_refund", function(data)
    self.clock = math.max(0, self.clock - (data.amount or 0) * 0.5)
  end)
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)  -- 弓の構え中はスローモーション
  self.clock = self.clock + dt
  local frac = clamp(self.clock / self.T, 0, 1)

  local intensity = 0
  if frac >= self.collapseAt then
    intensity = (frac - self.collapseAt) / math.max(1 - self.collapseAt, 0.001)
  end

  -- スローモーション中(弓の構え中)は +10 のフラグを乗せて送る
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local slow = (self.ts or 1) < 1 and 10 or 0
    scene:setMeshEffect(selfE, intensity + slow)
  end

  -- 崩壊境界がこの帯の中を通過している間だけ、境界から破片が飛び散る
  local bxNow = boundaryX(intensity)
  if intensity > 0.02 and intensity < 0.999 and
     bxNow > self.bx - self.halfW and bxNow < self.bx + self.halfW then
    self.emitAccum = self.emitAccum + dt
    if self.emitAccum > 0.12 then
      self.emitAccum = 0
      debris(bxNow + (math.random() - 0.5) * 1.2,
             self.by + (math.random() - 0.5) * self.halfH * 1.4,
             self.bz - 0.3, 4)
    end
  end

  if not self.suckFired and frac >= self.suckInAt then
    self.suckFired = true
    events:emit("bg_collapsed", {})
  end
end
