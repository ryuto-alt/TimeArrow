-- BgClockHands.lua -- 背景の大時計(BG_ClockRuin)の針。針エンティティ自身に付ける。
-- 秒針(tick=true)は1秒ごとに「カチッ」と弾んで進み(easeOutBack)、分針は滑らかに回る。
-- 先送り矢(time_skip=+量×0.5)/後戻り矢(time_rewind=-量×0.35、GameManagerの即時返金と
-- 同係数)で針が一気にスイープする。装飾なので視認性優先: 最大14倍速+2.5倍に誇張して
-- ブンッと回し、スイープ中は針先から火花を散らす。
properties = {
  { name = "degPerSec", type = "float", default = 6.0,  label = "1秒あたりの回転角(度)" },
  { name = "tick",      type = "bool",  default = true, label = "true=1秒ごとのチクタク / false=滑らか" },
}

local function easeOutBack(u)
  local c1, c3 = 1.70158, 2.70158
  local v = u - 1
  return 1 + c3 * v * v * v + c1 * v * v
end

function OnStart(self)
  self.clockT = 0     -- 針が指している時間(誇張スイープ込み)
  self.jump = 0       -- 消化待ちの時間ジャンプ(±)
  self.ts = 1.0
  self.baseRz = self.transform.rotation.z
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  events:on("time_skip", function(d)
    self.jump = self.jump + (d.amount or 0) * 0.5
  end)
  events:on("time_rewind", function(d)
    self.jump = self.jump - (d.amount or 0) * 0.35
  end)
end

function OnUpdate(self, dt)
  self.clockT = self.clockT + dt * (self.ts or 1)

  -- ジャンプ消化: 最大14倍速+2.5倍誇張(順=早回し/逆=巻き戻しがひと目で分かる)
  local sweeping = false
  if self.jump ~= 0 then
    local step = clamp(self.jump, -dt * 14.0, dt * 14.0)
    self.clockT = math.max(0, self.clockT + step * 2.5)
    self.jump = self.jump - step
    if math.abs(self.jump) < 0.001 then self.jump = 0 end
    sweeping = math.abs(self.jump) > 0.05
  end

  local t = self.clockT
  local ang
  if self.tick and not sweeping then
    -- 1秒ごとのチクタク(0.16秒でカチッと弾んで止まる)
    local s = math.floor(t)
    local u = (t - s) / 0.16
    if u > 1 then u = 1 end
    ang = -(s + easeOutBack(u)) * self.degPerSec
  else
    ang = -t * self.degPerSec
  end
  self.transform.rotation = Vec3.new(0, 0, self.baseRz + ang)

  -- スイープ中は針先から火花(回っていることを画面で主張する)
  if sweeping then
    local p = self.transform.position
    local s = self.transform.scale
    local len = 0.85 * s.x
    local rad = math.rad(ang + 90)   -- 針は+Y向きモデル、Z回転で振れる
    local tx = p.x + math.cos(rad) * len
    local ty = p.y + math.sin(rad) * len
    if self.jump > 0 then
      FX.trail(tx, ty, p.z - 0.3, 0.4, 0.85, 1.0)   -- 先送り=シアン
    else
      FX.trail(tx, ty, p.z - 0.3, 0.7, 0.45, 1.0)   -- 後戻り=紫
    end
  end
end