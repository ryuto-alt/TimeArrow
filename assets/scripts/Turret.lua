-- Turret.lua -- period ごとに左(-X)へ弾を撃つ砲台(Turretモデル)。弾に触れると死。
-- 弾はプール制: gen が "<自名>_p1".."_p3" のスプライトを用意しておく(このLuaが動かす)。
-- 【弾数有限】: ammo発を撃ち切ると沈黙する=待つのも一つの答え。
--   先送り矢: 未来へ飛ばして弾切れにさせる(無力化の正解)
--   後戻し矢: 時計が巻き戻り、撃った弾が銃口へ逆再生で吸い込まれ装弾も復活(+返金)
-- 引き絞り中は世界スローで弾もゆっくり=狙って抜ける快感を作る。
properties = {
  { name = "period",    type = "float", default = 2.4, min = 0.6, max = 10, label = "発射間隔(秒)" },
  { name = "shotSpeed", type = "float", default = 6.0, min = 1,   max = 20, label = "弾速" },
  { name = "range",     type = "float", default = 14.0, min = 3,  max = 40, label = "射程(これで消える)" },
  { name = "startPhase",type = "float", default = 0.0, min = 0,   max = 10, label = "開始位相(秒)" },
  { name = "ammo",      type = "int",   default = 10,  min = 1,   max = 99, label = "装弾数(撃ち切ると沈黙)" },
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
  self.clock = self.startPhase
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx - 0.8, self.by, self.bz, 8, 0.3, 0.75, 1.0)
  end)
  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name and data.target ~= self.name .. "X" then return end
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 0.5
    self.rwGlow = 0.1
    FX.spark(self.bx - 0.8, self.by, self.bz, 14, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 12, 8, 0.65, 0.4, 1.0)
  end)

end

-- 弾位置はクロックの純関数=先送り/後戻りで弾ごと未来/過去へ跳ぶ(可逆)
local function shotState(self, idx)
  -- idx番スロットの直近発射時刻
  local n = math.floor(self.clock / self.period) - idx
  if n < 0 or n >= self.ammo then return nil end   -- 弾数有限: 撃ち切ったスロットは出ない
  local t0 = n * self.period
  local flight = self.clock - t0
  local dist = flight * self.shotSpeed
  if dist > self.range then return nil end
  return self.bx - 0.9 - dist, self.by
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)
  self.clock = self.clock + dt
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
    end
  end

  local pl = scene:findEntity("Player")
  local pp = (pl and pl:isValid()) and pl.transform.position or nil

  for i = 0, 2 do
    local e = scene:findEntity(self.name .. "_p" .. (i + 1))
    if e and e:isValid() then
      local x, y = shotState(self, i)
      if x then
        e.transform.position = Vec3.new(x, y, self.bz)
        if self.ffRemain <= 0 and pp
           and math.abs(pp.x - x) < 0.42 and math.abs(pp.y - y) < 0.52 then
          events:emit("player_died", {})
        end
      else
        e.transform.position = Vec3.new(0, -100, 0)
      end
    end
  end

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0  -- 撃てる=金色の的アピール
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow > 0 then eff = 2.8 end
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
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(self.bx - 0.9, self.by, self.bz, 0.65, 0.4, 1.0)
  end
end
