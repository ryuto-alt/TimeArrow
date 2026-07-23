-- Bomb.lua -- 矢起爆式の爆弾。自分では爆発せず、先送り矢で導火線を累計 boomT 秒
-- 進めると爆発して隣接する Wall(wallTarget名)を破壊する(近くにいると爆風に巻き込まれる)。
-- 爆風は自分の transform.scale から出すAABBに blastScale 倍率をかけたもの。
properties = {
  { name = "boomT",      type = "float",  default = 5.0,  min = 0,   max = 60, label = "起爆に必要な先送り累計(秒)" },
  { name = "blastScale", type = "float",  default = 2.2,  min = 1,   max = 6,  label = "爆風の広がり(自身の見た目サイズに対する倍率)" },
  { name = "wallTarget", type = "string", default = "",                        label = "破壊するWallの名前(任意)" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  events:on("aim_preview", function(d)
    if d.target == self.name then self.aimPv = { m = d.mode, t = 0.12 } end
  end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.exploded = false
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name or self.exploded then return end
    -- 一括加算せず早送り(0.5秒で消化)。導火線が縮む間が生まれ、起爆に"溜め"がつく
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 1.5   -- ゆっくり消化(サージが速すぎて避けられない問題への全体調整)
    FX.spark(self.bx, self.by, self.bz, 10, 1.0, 0.7, 0.3)
  end)

  -- 後戻り(グローバル): 導火線が伸び直す。爆発済みは戻せない(破壊は不可逆)
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    if self.exploded then return end
    -- 後戻り矢: 一括減算せず逆再生(0.5秒で消化)して、巻き戻る様子を見せる
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 1.5   -- FFと同じ1.5秒消化(全ギミック統一テンポ。RWだけ3倍速で落下が速すぎた)
    self.rwGlow = 0.1
    local p = self.transform.position
    FX.spark(p.x, p.y, p.z, 10, 0.65, 0.4, 1.0)
    FX.shockwave(p.x, p.y, p.z, 10, 6, 0.65, 0.4, 1.0)
  end)
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)  -- 弓の構え中はスローモーション
  if self.exploded then return end
  -- 自走しない: 導火線(clock)は先送り矢の消化でのみ進む
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  if self.rwRemain and self.rwRemain > 0 then
    -- 対象の時計は0で底打ち。それ以上は戻せない=タイマー返金もされない(戻しすぎは無駄撃ち)
    local step = math.min(self.rwRemain, self.rwSpeed * dt, self.clock)
    if step <= 0 then
      self.rwRemain = 0
    else
      self.clock = self.clock - step
      self.rwRemain = self.rwRemain - step
      self.rwGlow = 0.1
      events:emit("time_refund", { amount = step })
    end
  end

  -- 見た目: 金色=撃てる / FF中=シアン / RW中=紫 / 照準ロック=帯8-9。
  -- 導火線が短くなるほど点滅が速くなる(残り3秒で危険を伝える)
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0
    local left = self.boomT - self.clock
    if left < 3.0 then
      eff = 6.0 + math.sin(self.clock * (18.0 - left * 4.0)) * 0.9  -- 経年帯で焦げていく
    end
    if self.ffRemain > 0 then eff = 1.0
    elseif (self.rwGlow or 0) > 0 then eff = 2.8 end
    if self.aimPv then
      self.aimPv.t = self.aimPv.t - dt
      if self.aimPv.t > 0 then eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
      else self.aimPv = nil end
    end
    scene:setMeshEffect(selfE, eff)
  end

  if self.clock < self.boomT then return end

  self.exploded = true
  FX.explosion(self.bx, self.by, self.bz, 1.3, 1.0, 0.5, 0.15)
  fx:pulse(0.5)
  audio:playSpatial("audio/se/explosion.wav", self.bx, self.by, self.bz, 4, 30, 1.0)
  self.transform.position = Vec3.new(self.bx, -100.0, self.bz)  -- 爆散して消える

  if self.wallTarget ~= "" then
    events:emit("wall_destroyed", { target = self.wallTarget })
  end

  local s = self.transform.scale
  local pl = scene:findEntity("Player")
  if pl and pl:isValid() then
    local pp, ps = pl.transform.position, pl.transform.scale
    if overlapAABB(self.bx, self.by, s.x * 0.5 * self.blastScale, s.y * 0.5 * self.blastScale,
                    pp.x, pp.y, 0.30, 0.42) then
      events:emit("player_died", {})
    end
  end
end
