-- CrumblePlatform.lua -- 乗ると崩壊カウントが始まる足場(Crumble_Plank)。
-- crumbleT 秒乗ると崩れ落ちる(揺れ→落下→消滅)。Player.standables に登録して使う。
-- 後戻り矢: 崩れた足場が巻き戻って復活する(実効量ぶん返金)=「崩した後に戻す」が本筋。
-- 先送り矢: 崩壊カウントが進む(乗る前に崩して先へ落とす、などの搦め手用)。
properties = {
  { name = "crumbleT", type = "float", default = 1.6, min = 0.3, max = 10, label = "乗ってから崩れるまでの秒数" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  events:on("aim_preview", function(d)
    if d.target == self.name or d.target == self.name .. "X" then
      self.aimPv = { m = d.mode, t = 0.12 }
    end
  end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0           -- 崩壊クロック(乗っている間+落下後は進み続ける)
  self.armed = false       -- 一度でも乗ったらtrue
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.armed = true
    self.ffRemain = self.ffRemain + (data.amount or 0)
    self.ffSpeed = self.ffRemain / 1.5   -- ゆっくり消化(サージが速すぎて避けられない問題への全体調整)
    FX.spark(self.bx, self.by, self.bz, 8, 0.3, 0.75, 1.0)
  end)

  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 1.5   -- FFと同じ1.5秒消化(全ギミック統一テンポ。RWだけ3倍速で落下が速すぎた)
    self.rwGlow = 0.1
    FX.spark(self.bx, self.by, self.bz, 10, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.65, 0.4, 1.0)
  end)

end

local function playerOnTop(self)
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return false end
  local pp = pl.transform.position
  local s = self.transform.scale
  local top = self.by + s.y * 0.5
  return math.abs(pp.x - self.bx) < (s.x * 0.5 + 0.4)
     and math.abs((pp.y - 0.55) - top) < 0.25
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)

  if not self.armed and playerOnTop(self) then
    self.armed = true
    FX.spark(self.bx, self.by + 0.3, self.bz, 6, 1.0, 0.8, 0.4)
  end

  if self.armed then
    self.clock = self.clock + dt
  end
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  if self.rwRemain and self.rwRemain > 0 then
    local step = math.min(self.rwRemain, self.rwSpeed * dt, self.clock)
    if step <= 0 then
      self.rwRemain = 0
    else
      self.clock = self.clock - step
      self.rwRemain = self.rwRemain - step
      self.rwGlow = 0.1
      events:emit("time_refund", { amount = step })
      if self.clock <= 0 then self.armed = false end   -- 完全に巻き戻したら未使用状態へ
    end
  end

  -- 状態→位置: 崩壊前=揺れ / 崩壊後=落下(クロックに比例した深さ=巻き戻しで戻れる)
  local x, y = self.bx, self.by
  if self.clock > 0 and self.clock < self.crumbleT then
    local f = self.clock / self.crumbleT
    x = self.bx + math.sin(self.clock * 40) * 0.05 * f     -- ガタガタ予告
    if f > 0.6 then
      FX.trail(self.bx, self.by - 0.2, self.bz, 0.8, 0.7, 0.5)
    end
  elseif self.clock >= self.crumbleT then
    local fall = (self.clock - self.crumbleT)
    y = self.by - math.min(60, fall * fall * 6.0)           -- 加速落下(クロック関数=可逆)
  end
  self.transform.position = Vec3.new(x, y, self.bz)

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0  -- 撃てる=金色の的アピール
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow and self.rwGlow > 0 then eff = 2.8 end
    if self.aimPv then
      self.aimPv.t = self.aimPv.t - dt
      if self.aimPv.t > 0 then
        eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
      else
        self.aimPv = nil
      end
    end
    scene:setMeshEffect(selfE, eff)
  end
  if self.rwGlow and self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(x, y, self.bz, 0.65, 0.4, 1.0)
  end
end
